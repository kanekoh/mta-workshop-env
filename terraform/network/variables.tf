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
  description = "Name of the ROSA cluster (used for resource naming)"
  type        = string
  default     = "mta-lightspeed"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default = {
    Environment = "Workshop"
    Project     = "MTA-for-Developer-Lightspeed"
  }
}

