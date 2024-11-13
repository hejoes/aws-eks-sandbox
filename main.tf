# for following providers to work, awscli has to be installed locally
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}


################################################################################
# EKS Module
################################################################################

module "ebs_csi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "${var.eks_cluster}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.eks_cluster
  cluster_version = "1.30"

  # ref: https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/karpenter/
  # Give the Terraform identity admin access to the cluster
  # which will allow it to deploy resources into the cluster
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true #by default when manually creating eks, is set to true, but in eks module is set to false. For sandbox purposes will keep it true.

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Needed by the aws-ebs-csi-driver
  iam_role_additional_policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
      most_recent              = true
    }
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
        resources = {
          limits = {
            cpu    = "0.25"
            memory = "256M"
          }
          requests = {
            cpu    = "0.25"
            memory = "256M"
          }
        }
      })
    }
  }

  # Not needed when running on fargate
  create_cluster_security_group = false
  create_node_security_group    = false


  fargate_profiles = {
    test = {
      selectors = [
        { namespace = "test" }
      ]
    }
    app = {
      selectors = [
        { namespace = "app" }
      ]
    }
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    kube-system = {
      selectors = [
        { namespace = "kube-system" }
      ]
    }
  }

  tags = merge(var.common_tags, {
    "karpenter.sh/discovery" = var.eks_cluster #Name of eks cluster m
  })
}

################################################################################
# Karpenter
################################################################################
locals {
  namespace = "karpenter"
}

module "karpenter" {
  source    = "terraform-aws-modules/eks/aws//modules/karpenter"
  version   = "~> 20.24"
  namespace = local.namespace

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = false
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn

  enable_v1_permissions = true

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = module.eks.cluster_name # could change later to eks name
  tags                          = var.common_tags

}

resource "helm_release" "karpenter" {
  namespace        = local.namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.6"
  wait       = false


  values = [
    <<-EOT
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueueName: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn} 
    webhook:
      enabled: false
    EOT
  ]

  depends_on = [module.karpenter, module.eks]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
        - alias: bottlerocket@latest
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            # Not needed, as karpenter can figure out best instance type for our workloads itself
            # - key: "karpenter.k8s.aws/instance-category"
            #   operator: In
            #   values: ["t2", "t3"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
      limits:
        cpu: 12
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class

  ]
}

#test deployment: kubectl scale deployment inflate --replicas 5
# resource "kubectl_manifest" "karpenter_example_deployment" {
#   yaml_body = <<-YAML
#     apiVersion: apps/v1
#     kind: Deployment
#     metadata:
#       name: inflate
#     spec:
#       replicas: 0
#       selector:
#         matchLabels:
#           app: inflate
#       template:
#         metadata:
#           labels:
#             app: inflate
#         spec:
#           terminationGracePeriodSeconds: 0
#           containers:
#             - name: inflate
#               image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
#               resources:
#                 requests:
#                   cpu: 0.5
#                   memory: 520M
#   YAML

#   depends_on = [
#     helm_release.karpenter
#   ]
# }


# resource "helm_release" "cilium" {
#   name             = "cilium"
#   namespace        = "kube-system"
#   repository       = "https://helm.cilium.io/"
#   chart            = "cilium"
#   version          = "1.14.4"
#   create_namespace = false
#
#   values = [
#     <<-EOT
#       kubeProxyReplacement: "strict"
#       k8sServiceHost: ${module.eks.cluster_endpoint}
#       k8sServicePort: 443
#       hostServices:
#         enabled: false
#       externalIPs:
#         enabled: true
#       nodePort:
#         enabled: true
#       hostPort:
#         enabled: true
#       image:
#         pullPolicy: IfNotPresent
#       ipam:
#         mode: kubernetes
#       hubble:
#         enabled: true
#         relay:
#           enabled: true
#         ui:
#           enabled: true
#       EOT
#   ]
#
#   depends_on = [module.eks]
# }

################################################################################
# Outputs
################################################################################


# output "eks cluster arn" {
#   value       = module.eks.cluster_arn
#   description = "The cluster identifyiable arn"
# }
#
output "useful_commands" {
  description = "Useful commands to help you get started"
  value       = <<EOT
    
    Quick start:
    --------------------
    Setup kubectl:
       aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}

  EOT
}

