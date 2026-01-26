resource "tls_private_key" "ed25519" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  key_name   = var.aws_ssh_key_name
  public_key = tls_private_key.ed25519.public_key_openssh

  tags = {
    Name = var.aws_ssh_key_name
  }
}
