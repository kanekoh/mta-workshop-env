# Network Information
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.rosa_vpc.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.rosa_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for subnet in aws_subnet.rosa_public_subnet : subnet.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for subnet in aws_subnet.rosa_private_subnet : subnet.id]
}

output "all_subnet_ids" {
  description = "All subnet IDs (public + private)"
  value       = concat(
    [for subnet in aws_subnet.rosa_public_subnet : subnet.id],
    [for subnet in aws_subnet.rosa_private_subnet : subnet.id]
  )
}

output "availability_zones" {
  description = "Availability zones used"
  value       = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)
}

