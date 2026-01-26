variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "aws_ssh_key_name" {
  description = "Name for the key pair. If empty, a new key pair will be created. If provided, the existing key pair with this name will be used."
  type        = string
  default     = ""
}

variable "aws_ec2_instance_type" {
  description = "EC2 instance type to deploy"
  type        = string
  default     = "t2.micro"
}

variable "aws_ec2_instance_name" {
  description = "Name tag to assign to the EC2 instance"
  type        = string
  default     = "ps-centos-10"
}

variable "aws_vpc_id" {
  description = "ID of the specific VPC to deploy into."
  type        = string
}

variable "aws_subnet_id" {
  description = "ID of the specific Subnet to deploy into. Optional (if empty, first subnet in vpc gets picked)."
  type        = string
  default     = ""
}

variable "aws_ec2_instance_root_volume_size" {
  description = "Size (in GiB) of the root EBS volume attached to the created EC2 instance"
  type        = number
  default     = 20
}

variable "tags" {
  description = "A map of tags, currently only added to the EC2 instance and its EBS disk(s)"
  type        = map(string)
  default     = {}
}
