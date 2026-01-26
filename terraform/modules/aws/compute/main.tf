# Provider configuration is passed from the calling module

locals {
  vpc_id         = var.aws_vpc_id
  ssh_sg_name    = "${var.name}-ssh-in-only-sg"
  egress_sg_name = "${var.name}-egress-all-sg"
  instance_name  = "${var.name}-ec2"
}

resource "aws_security_group" "ssh" {
  count       = var.create_default_sgs ? 1 : 0
  name        = local.ssh_sg_name
  description = "Only Allow Inbound SSH Traffic"
  vpc_id      = local.vpc_id

  ingress {
    description = "Allow Inbound SSH Traffic"
    # from -> to is the port range; from_port != client/peer port
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.ssh_sg_name
  }
}

resource "aws_security_group" "egress_all" {
  count       = var.create_default_sgs ? 1 : 0
  name        = local.egress_sg_name
  description = "Allow All Outbound Traffic"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.egress_sg_name
  }
}

data "aws_ami" "centos_stream" {
  most_recent = true
  owners      = ["125523088429"] # CentOS Official Account

  filter {
    name   = "name"
    values = ["CentOS Stream 10 x86_64 *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_subnets" "in_vpc" {
  filter {
    name   = "vpc-id"
    values = [var.aws_vpc_id]
  }
}

resource "aws_instance" "this" {
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.centos_stream.id
  instance_type               = var.aws_instance_type
  key_name                    = var.aws_ssh_key_name
  associate_public_ip_address = true
  disable_api_stop            = true

  subnet_id = var.aws_subnet_id != "" ? var.aws_subnet_id : tolist(data.aws_subnets.in_vpc.ids)[0]

  # Concatenate the internal SGs (if created) with any external SGs passed in
  vpc_security_group_ids = concat(
    var.create_default_sgs ? [aws_security_group.ssh[0].id, aws_security_group.egress_all[0].id] : [],
    var.vpc_security_group_ids
  )

  # Merge input tags with the Name tag.
  # Note: var.tags comes first so that the local 'Name' value overrides any collision.
  tags = merge(
    var.tags,
    {
      Name = local.instance_name
    }
  )

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    encrypted   = true
    tags = merge(
      var.tags,
      {
        Name = "${local.instance_name}-root-vol"
      }
    )
  }

  user_data = var.user_data
}
