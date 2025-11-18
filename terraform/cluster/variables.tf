variable "aws_region" {
  description = "AWS region where ROSA cluster will be deployed"
  type        = string
  default     = "ap-northeast-1"
}

# AWS認証情報は環境変数から自動的に読み込まれます:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# terraform.tfvarsでの設定は不要です

variable "cluster_name" {
  description = "Name of the ROSA cluster"
  type        = string
  default     = "mta-lightspeed"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (must match network module)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ocp_version" {
  description = "OpenShift version to deploy"
  type        = string
  default     = "4.19"
}

variable "rosa_machine_type" {
  description = "Instance type for ROSA compute nodes"
  type        = string
  default     = "m6a.2xlarge"
}

variable "rosa_replicas" {
  description = "Number of compute node replicas"
  type        = number
  default     = 2
}

variable "availability_zone_count" {
  description = "Number of availability zones to use (must match network module)"
  type        = number
  default     = 1
}

variable "billing_account" {
  description = "AWS billing account ID for ROSA"
  type        = string
  default     = ""
}

variable "create_admin_user" {
  description = "Whether to create an admin user for the cluster"
  type        = bool
  default     = true
}

variable "cluster_admin_username" {
  description = "Username for the cluster admin user. If not specified, module default will be used."
  type        = string
  default     = null
  sensitive   = false
}

variable "cluster_admin_password" {
  description = "Password for the cluster admin user. If not specified, module will generate a random password."
  type        = string
  default     = null
  sensitive   = true
}

variable "admin_password" {
  description = "Password for admin user (HTPasswd IDP). If not provided, admin IDP will not be created."
  type        = string
  default     = null
  sensitive   = true
}

variable "admin_count" {
  description = "Number of admin users to create (admin, admin2, ...)."
  type        = number
  default     = 1
}

variable "developer_password" {
  description = "Password for developer user (HTPasswd IDP). If not provided, developer IDP will not be created."
  type        = string
  default     = null
  sensitive   = true
}

variable "workshop_user_password" {
  description = "Password for workshop users (user1-userN, HTPasswd IDP). If not provided, workshop users IDP will not be created."
  type        = string
  default     = null
  sensitive   = true
}

variable "workshop_user_count" {
  description = "Number of workshop users to create (user1..userN)."
  type        = number
  default     = 20
}

# Network outputs from network module (passed via remote state or outputs file)
variable "vpc_id" {
  description = "VPC ID from network module"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from network module"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from network module"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones from network module"
  type        = list(string)
}

# Additional MachinePools (2nd pool and beyond)
# The first MachinePool is created automatically by module.rosa_hcp and cannot be deleted.
variable "additional_machine_pools" {
  description = "List of additional MachinePools to create. The first MachinePool is managed by module.rosa_hcp."
  type = list(object({
    name          = string
    instance_type = string
    replicas      = number
    auto_repair   = optional(bool, true)  # Enable auto repair for the machine pool (default: true)
    autoscaling   = optional(object({
      enabled     = bool
      min_replicas = optional(number)
      max_replicas = optional(number)
    }), { enabled = false })  # Autoscaling configuration (default: disabled)
    subnet_id     = optional(string)  # Subnet ID for the machine pool. If not specified, uses first private subnet.
    # Note: For Single-AZ, specify a subnet_id in the desired AZ.
    # For Multi-AZ, if subnet_id is not specified, the cluster will use its default subnets across all AZs.
    # However, rhcs_hcp_machine_pool requires subnet_id, so it will use the specified subnet or default to first private subnet.
    labels        = optional(map(string), {})
    taints        = optional(list(object({
      key    = string
      value  = string
      effect = string  # NoSchedule, PreferNoSchedule, or NoExecute
    })), [])
  }))
  default = []
}

