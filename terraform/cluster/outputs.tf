# Cluster Information
output "cluster_id" {
  description = "ROSA Cluster ID"
  value       = local.cluster_id
}

output "cluster_name" {
  description = "ROSA Cluster Name"
  value       = var.cluster_name
}

output "cluster_api_url" {
  description = "ROSA Cluster API URL"
  value       = module.rosa_hcp.cluster_api_url
}

output "cluster_console_url" {
  description = "ROSA Cluster Console URL"
  value       = module.rosa_hcp.cluster_console_url
}

output "cluster_domain" {
  description = "ROSA Cluster Domain"
  value       = module.rosa_hcp.cluster_domain
}

# Admin User Information
output "cluster_admin_username" {
  description = "Cluster admin username"
  value       = var.create_admin_user ? module.rosa_hcp.cluster_admin_username : "N/A"
  sensitive   = true
}

output "cluster_admin_password" {
  description = "Cluster admin password (sensitive)"
  value       = var.create_admin_user ? module.rosa_hcp.cluster_admin_password : "N/A"
  sensitive   = true
}

# OIDC Information
output "oidc_config_id" {
  description = "OIDC Config ID"
  value       = module.rosa_hcp.oidc_config_id
}

output "oidc_endpoint_url" {
  description = "OIDC Endpoint URL"
  value       = module.rosa_hcp.oidc_endpoint_url
}

# AWS Information
output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "devspaces_role_arn" {
  description = "AWS IAM Role ARN for DevSpaces ServiceAccount"
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-operator-roles-devspaces"
}

# Ansible Inventory Output (JSON format)
output "ansible_inventory_json" {
  description = "JSON output for Ansible inventory"
  value = jsonencode({
    cluster = {
      name        = var.cluster_name
      id          = module.rosa_hcp.cluster_id
      api_url     = module.rosa_hcp.cluster_api_url
      console_url = module.rosa_hcp.cluster_console_url
      domain      = module.rosa_hcp.cluster_domain
      region      = var.aws_region
      version     = var.ocp_version
    }
    admin_user = {
      username = var.create_admin_user ? module.rosa_hcp.cluster_admin_username : ""
      password = var.create_admin_user ? module.rosa_hcp.cluster_admin_password : ""
    }
    network = {
      vpc_id             = var.vpc_id
      vpc_cidr           = var.vpc_cidr
      public_subnet_ids  = var.public_subnet_ids
      private_subnet_ids = var.private_subnet_ids
    }
  })
  sensitive = true
}

