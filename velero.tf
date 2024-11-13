#Velero
resource "aws_s3_bucket" "velero" {
  bucket = var.velero_bucket

  tags = {
    Name = var.velero_bucket
  }
}


resource "aws_s3_bucket_policy" "velero" {
  bucket = aws_s3_bucket.velero.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Velero"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.velero.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListBucketVersions",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          aws_s3_bucket.velero.arn,
          "${aws_s3_bucket.velero.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "velero" {
  name        = "velero-${var.eks_cluster}"
  description = "Policy for Velero backup and restore"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          aws_s3_bucket.velero.arn,
          "${aws_s3_bucket.velero.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "velero" {
  name = "velero-${var.eks_cluster}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:velero:velero",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "velero" {
  policy_arn = aws_iam_policy.velero.arn
  role       = aws_iam_role.velero.name
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration {
    status = "Enabled"
  }
}

module "velero" {
  source  = "terraform-module/velero/kubernetes"
  version = "1.2.0"

  namespace_deploy            = true
  app_deploy                  = true
  cluster_name                = module.eks.cluster_name
  bucket                      = var.velero_bucket
  openid_connect_provider_uri = module.eks.oidc_provider

  values = [templatefile("${path.module}/helm-files/velero.yaml", {
    velero_bucket       = var.velero_bucket
    eks_cluster         = var.eks_cluster
    region              = var.region
    service_account_arn = aws_iam_role.velero.arn
  })]

  # only deploy after all karpenter resources have been created, otherwise no nodes will be provisioned for velero
  depends_on = [
    kubectl_manifest.karpenter_node_pool
  ]
}
