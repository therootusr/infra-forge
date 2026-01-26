module "key_pair" {
  source = "../../../modules/aws/key-pair"
  # Only create a new key pair IF the user did NOT provide an existing aws_ssh_key_name
  count            = var.aws_ssh_key_name == "" ? 1 : 0
  aws_ssh_key_name = "ps-ssh-key-1-ed25519-${var.aws_region}"
}

module "aws_compute" {
  source            = "../../../modules/aws/compute"
  name              = var.aws_ec2_instance_name
  aws_vpc_id        = var.aws_vpc_id
  aws_subnet_id     = var.aws_subnet_id
  aws_instance_type = var.aws_ec2_instance_type
  tags              = var.tags
  root_volume_size  = var.aws_ec2_instance_root_volume_size

  # cloud-init user data script run on first boot
  user_data = file("${path.module}/../../../../scripts/setup_vm.sh")

  # Logic: Use the newly created key name (if we made one) OR the user-provided existing name
  aws_ssh_key_name = var.aws_ssh_key_name == "" ? module.key_pair[0].key_name : var.aws_ssh_key_name
  # Note: The aws_region input here is actually unused by the module currently (it uses provider context),
  # but passing it is harmless. The REAL region is enforced by the provider block in versions.tf
  # aws_region      = var.aws_region
}
