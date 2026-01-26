variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "tags" {
  description = "A map of tags, currently only added to the EC2 instance and its EBS disk(s)"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI ID to use. If empty, will search for latest CentOS Stream 10."
  type        = string
  default     = ""
}

variable "aws_vpc_id" {
  description = "ID of the specific VPC to deploy into."
  type        = string
}

variable "aws_subnet_id" {
  description = "ID of the specific Subnet to deploy into. If empty, the first available subnet in the VPC will be used."
  type        = string
  default     = ""
}

variable "aws_ssh_key_name" {
  description = "The name of the EC2 Key Pair to attach to the instance."
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
}

variable "root_volume_type" {
  description = "Type of the root EBS volume (gp3 is recommended for balance of price/performance and scaling)"
  type        = string
  default     = "gp3"
}

variable "user_data" {
  description = "User data script to initialize the instance"
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of existing Security Group IDs to attach to the instance"
  type        = list(string)
  default     = []
}

variable "create_default_sgs" {
  description = "Whether to create the default SSH and Egress security groups inside this module"
  type        = bool
  default     = true
}
