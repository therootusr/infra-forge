output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.aws_compute.instance_id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.aws_compute.public_ip
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.aws_compute.private_ip
}

output "private_key_pem" {
  description = "Private SSH key (save to file and chmod 600)"
  value       = var.aws_ssh_key_name == "" ? module.key_pair[0].private_key_pem : null
  sensitive   = true
}
