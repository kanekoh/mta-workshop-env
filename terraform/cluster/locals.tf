locals {
  cluster_id  = module.rosa_hcp.cluster_id
  admin_group = "cluster-admins"

  # 初期 Worker Machine Pool の replicas（構築時のみ有効・変更不可）
  # Single-AZ (private subnet 1) = 2, Multi-AZ (3 subnets) = 3（ROSA の「private subnets の倍数」）
  initial_worker_replicas = length(var.private_subnet_ids) == 1 ? 2 : 3

  # 管理者ユーザー名: admin / admin2 / admin3 ...
  admin_usernames = var.admin_count == 1 ? [
    "admin"
  ] : concat(
    ["admin"],
    [for i in range(2, var.admin_count + 1) : "admin${i}"]
  )

  developer_username = "developer"

  # ワークショップユーザー名: user1 .. userN
  workshop_usernames = [
    for i in range(1, var.workshop_user_count + 1) : "user${i}"
  ]

  # 現在のAWS認証情報からIAMユーザー名を抽出
  # ARN形式: arn:aws:iam::ACCOUNT_ID:user/USER_NAME
  # IAMロールの場合は: arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME または arn:aws:sts::ACCOUNT_ID:assumed-role/ROLE_NAME/SESSION_NAME
  # split()とelement()を使ってARNからユーザー名を抽出（シンプルな方法）
  arn_parts = split(":", data.aws_caller_identity.current.arn)
  resource_part = length(local.arn_parts) >= 6 ? element(local.arn_parts, 5) : ""
  resource_parts = split("/", local.resource_part)
  current_user_name = startswith(local.resource_part, "user/") && length(local.resource_parts) >= 2 ? element(local.resource_parts, 1) : null

  # IAM User ARN (admin_user_nameが指定されている場合はそれを使用、そうでなければ現在のユーザー名を使用)
  admin_user_name = var.admin_user_name != null && var.admin_user_name != "" ? var.admin_user_name : local.current_user_name

  admin_user_arn = local.admin_user_name != null && local.admin_user_name != "" ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${local.admin_user_name}" : null
}

