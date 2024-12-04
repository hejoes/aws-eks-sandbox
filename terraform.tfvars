region   = "eu-north-1"
vpc_cidr = "10.0.0.0/16"

common_tags = {
  Terraform   = "true"
  Environment = "Homelab"
}


eks_cluster   = "EKS-Sandbox"
velero_bucket = "hejoes-velero-eks"
