region   = "eu-north-1"
vpc_cidr = "10.0.0.0/16"

public_subnet = {
  "eu-north-1a" = "10.0.101.0/24"
  "eu-north-1b" = "10.0.103.0/24"
}

private_subnet = {
  "eu-north-1a" = "10.0.104.0/24"
  "eu-north-1b" = "10.0.105.0/24"
}

common_tags = {
  Terraform   = "true"
  Environment = "Homelab"
}


eks_cluster   = "EKS-Sandbox"
velero_bucket = "hejoes-velero-eks"
