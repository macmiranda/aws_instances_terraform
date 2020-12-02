provider "aws" {
  region = "eu-central-1"
}

locals {
  user_data = <<EOF
#!/bin/bash
apt update && apt install -y git
EOF
}

##################################################################
# Data sources to get VPC, subnet, security group and AMI details
##################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "simple-example"
  description = "Security group for example usage with EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "https-443-tcp", "ssh-tcp", "all-icmp", ]
  ingress_with_cidr_blocks = [
    {
      from_port   = 30000
      to_port     = 32767
      protocol    = 6
      description = "kube-proxy"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_rules        = ["all-all"]
}

resource "aws_eip" "this" {
  vpc      = true
  instance = module.ec2.id[0]
}

resource "aws_network_interface" "this" {
  count = 1

  subnet_id = tolist(data.aws_subnet_ids.all.ids)[count.index]
}

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "2.15.0"
  instance_count = 2
  key_name      = "cdtc_key"
  name          = "simple-instance"
  ami           = "ami-01d4d9d5d6b52b25e"
  instance_type = "t2.small"
  subnet_id     = tolist(data.aws_subnet_ids.all.ids)[0]
  vpc_security_group_ids      = [module.security_group.this_security_group_id]
  associate_public_ip_address = true
  user_data_base64 = base64encode(local.user_data)
  root_block_device = [
    {
      volume_type = "gp2"
      volume_size = 10
    },
  ]
  tags = {
    "cluster"      = "kubernetes"
  }
}
