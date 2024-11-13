# output "aws_account_id" {
#   value = data.aws_caller_identity.current.account_id
# }

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "vpc_cidr" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "eks_cluster" {
  type = string
}

# variable "public_subnet" {
#   type = map(string)
#   default = {
#     "eu-north-1a" = "10.0.101.0/24"
#     "eu-north-1b" = "10.0.103.0/24"
#   }
# }

# variable "private_subnet" {
#   type = map(string)
#   default = {
#     "eu-north-1a" = "10.0.104.0/24"
#     "eu-north-1b" = "10.0.105.0/24"
#   }
# }

variable "velero_bucket" {
  type        = string
  description = "Name of the S3 bucket for Velero backups. Must be globally unique."
}
