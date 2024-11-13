# EKS-Sandbox 🚀

This repo can be used to create sandbox EKS fargate cluster that uses Karpenter
to provision nodes based on pods memory/cpu usage. After EKS & Karpenter, it
sets up Velero and s3 bucket for backups & DR.

SQS and EventBridge are created under karpenter submodule to handle spot
interruptions and spin up new node, drain old node and move pods over before the
old spot node is removed.

- [Prerequisites 🛠️](#prerequisites-️)
- [Costs 💰](#costs-)
- [Usage 🔧](#usage)
  - [Running the Script ⚡](#running-the-script-)
  - [Debugging 🔍](#debugging-)
  - [Testing Karpenter 📈](#testing-karpenter-automatic-node-scaling-)
  - [Cleanup 🗑️](#cleanup-️)

## Prerequisites 🛠️

- AWS account
- AWS CLI installed and configured
- Terraform installed
- Exported AWS Access and Secret Key

## Costs 💰

### Estimated monthly Costs

- EKS Control Plane ~65€/monthly
- Fargate ~0.03€ per pod/h
- Karpenter managed ec2: Depends on deployed workloads outside fargate managed
  namespaces (test, app, kube-system, karpenter)

**Total ~80€/monthly**

> [!TIP]
> In order to reduce costs, just use the infra when you need to do kubernetes
> testing and destroy it later. You can do workload backups with Velero and
> restore from S3 after rebuild.

## Usage

- Currently following namespaces are Faregate managed `kube-system`,
  `karpenter`, `test`, `app`. Doing any other deploys to namespaces outside
  them, triggers Karpenter autoscaler.

### Running the script ⚡

1. Go to `terraform.tfvars`
1. Change velero_bucket and eks_cluster to desired values. Add more common_tags
   if needed.
1. `terraform apply --auto-approve`
1. The TF output gives you automatically cmd for configuring kubectl to access
   the cluster:
   - `aws eks --region eu-north-1 update-kubeconfig --name $TF_VARS_EKS_CLUSTER`

> [!NOTE]
> TF build and destroy take ~20min

### Debugging 🔍

> [!TIP]
> If somehow on the first run you get karpenter context deadline exceeded, just
> run apply again.

### Testing Karpenter's Automatic Node Scaling 📈

Instructions taken from:
https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/#6-scale-up-deployment

`kubectl scale deployment inflate --replicas 5`
`kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter -c controller`

### Cleanup 🗑️

> [!IMPORTANT]
> Ec2's that Karpenter has provisioned will not be cleaned up with `tf destroy`.
> These should be removed manually `kubectl delete node`

1. Make sure all nodes have successfully been shut down.
1. Run `terraform destroy`
