# Additional MachinePools for ROSA HCP Cluster
# 
# Note: The first MachinePool is automatically created by module.rosa_hcp
# and cannot be deleted. This file manages additional MachinePools (2nd and beyond).
#
# These MachinePools are useful for:
# - OpenShift AI workloads requiring GPU instances
# - Workloads with specific resource requirements
# - Isolating workloads by node type
#
# IMPORTANT: MachinePool作成時の認証について
# - サービスアカウント（RHCS_CLIENT_ID / RHCS_CLIENT_SECRET）では
#   403エラーが発生する場合があります。
# - その場合は、RHCS_TOKENを使用してください:
#     rosa login --use-auth-code  # または --use-device-code
#     export RHCS_TOKEN=$(rosa token)
# - RHCS_TOKENは一時トークンで有効期限が短いため、長時間の操作には注意が必要です。

resource "rhcs_hcp_machine_pool" "additional" {
  for_each = {
    for idx, pool in var.additional_machine_pools : pool.name => pool
  }

  cluster  = local.cluster_id
  name     = each.value.name
  replicas = each.value.replicas

  # AWS Node Pool configuration
  aws_node_pool = {
    instance_type = each.value.instance_type
    # Additional settings can be added here if needed:
    # disk_size = ...
    # tags = ...
  }

  # Auto repair (required, configurable via variable)
  auto_repair = each.value.auto_repair

  # Autoscaling (required, configurable via variable, default: disabled)
  autoscaling = {
    enabled      = each.value.autoscaling.enabled
    min_replicas = each.value.autoscaling.min_replicas
    max_replicas = each.value.autoscaling.max_replicas
  }

  # Subnet ID (required)
  # If specified in variable, use it. Otherwise, use first private subnet.
  # Note: For Multi-AZ clusters, specifying a subnet_id will create a Single-AZ machine pool in that subnet's AZ.
  # For Multi-AZ machine pools, you may need to create separate machine pools for each AZ, or rely on cluster's default behavior.
  subnet_id = each.value.subnet_id != null ? each.value.subnet_id : var.private_subnet_ids[0]

  # Note: availability_zone is read-only (computed) attribute.
  # Single-AZ vs Multi-AZ is determined by the subnet_id and cluster configuration.
  # For Multi-AZ machine pools, you may need to create multiple machine pools (one per AZ) or use cluster's default subnets.

  # Labels for node selection
  labels = each.value.labels

  # Taints for node scheduling control (optional)
  # Note: schedule_type corresponds to effect (NoSchedule, PreferNoSchedule, NoExecute)
  # If taints is empty, omit the attribute entirely (don't set to empty list)
  taints = length(each.value.taints) > 0 ? [
    for taint in each.value.taints : {
      key           = taint.key
      value         = taint.value
      schedule_type = taint.effect  # effect is mapped to schedule_type
    }
  ] : null

  depends_on = [module.rosa_hcp]
}

