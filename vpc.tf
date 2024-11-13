data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  #otherwise issues with multiple aws dependency contraints
  version = "5.15.0"

  name = "${var.eks_cluster}-VPC"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # for Karpenter auto-discovery, only private subnets can be targeted cause fargate runs only on private
    "karpenter.sh/discovery" = var.eks_cluster
  }

  tags = merge(var.common_tags, {
    Name = "${var.eks_cluster}-VPC"
  })
}

# resource "aws_vpc" "homelab" {
#   cidr_block           = var.vpc_cidr
#   enable_dns_hostnames = true
#   tags = merge(var.common_tags, {
#     Name = "${var.common_tags.Environment}-VPC"
#   })
# }

# resource "aws_subnet" "public" {
#   for_each          = var.public_subnet
#   vpc_id            = aws_vpc.homelab.id
#   cidr_block        = each.value
#   availability_zone = each.key

#   map_public_ip_on_launch = true

#   tags = merge(var.common_tags, {
#     Name = "${var.common_tags.Environment}-Public-${each.key}"
#   })
# }

# resource "aws_subnet" "private" {
#   for_each          = var.private_subnet
#   vpc_id            = aws_vpc.homelab.id
#   cidr_block        = each.value
#   availability_zone = each.key

#   tags = merge(var.common_tags, {
#     Name = "${var.common_tags.Environment}-Private-${each.key}"
#     "karpenter.sh/discovery" = var.eks_cluster #BASED ON EKS NAME
#   })
# }

# resource "aws_internet_gateway" "homelab_igw" {
#   vpc_id = module.vpc.vpc_id
#   tags = merge(var.common_tags, {
#     Name = "${var.eks_cluster}-IGW"
#   })
# }

# # Associating the Internet Gateway to the default Route Table (RT)
# resource "aws_default_route_table" "main_vpc_default_rt" {
#   default_route_table_id = module.vpc.default_route_table_id

#   route {
#     cidr_block = "0.0.0.0/0" # default route
#     gateway_id = aws_internet_gateway.homelab_igw.id
#   }
#   tags = {
#     "Name" = "${var.eks_cluster}-RT"
#   }
# }

resource "aws_security_group" "homelab_sec_group" {
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # cidr_blocks = [var.my_public_ip]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.common_tags, {
    Name = "${var.eks_cluster}-SG"
  })
}

