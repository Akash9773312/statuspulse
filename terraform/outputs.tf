output "server_ip" {
  description = "Stable Elastic IP assigned to the instance"
  value       = aws_eip.statuspulse.public_ip
}

output "elastic_ip_allocation_id" {
  description = "Elastic IP allocation ID (persists across instance replacements)"
  value       = aws_eip.statuspulse.id
}

output "domain_name" {
  value = var.domain_name
}

output "ssh_user" {
  value = var.ssh_user
}

output "app_url" {
  value = "https://${var.domain_name}"
}
