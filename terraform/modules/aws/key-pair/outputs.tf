output "key_name" {
  description = "The key name that was created"
  value       = aws_key_pair.this.key_name
}

output "private_key_pem" {
  description = "The private key data in OpenSSH format"
  value       = tls_private_key.ed25519.private_key_openssh
  sensitive   = true
}

output "public_key_openssh" {
  description = "The public key data in OpenSSH format"
  value       = tls_private_key.ed25519.public_key_openssh
}
