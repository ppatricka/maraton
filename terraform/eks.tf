# -----------------------------------------------------------------------------
# EKS: the Kubernetes cluster that runs the Maratón web app.
#   - Worker nodes live in the PRIVATE subnets (no public IPs).
#   - The API endpoint is public and open to any IP (0.0.0.0/0) so GitHub
#     Actions runners (whose IPs change) can deploy. Every request still needs
#     a valid AWS IAM identity that has an EKS access entry. A private endpoint
#     is also on so nodes talk to the control plane inside the VPC.
#   - Control-plane logging (api, audit, authenticator) goes to CloudWatch:
#     this is the exercise's "control plane audit logging" requirement.
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31" # v20 is the line that works with AWS provider 5.x

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets # worker nodes
  control_plane_subnet_ids = module.vpc.private_subnets # control-plane network interfaces

  # TRADE-OFF (decided in step 7): reachable from any IP, authenticated by IAM.
  # Production answer: private endpoint + a self-hosted runner or GitOps pull model.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  cluster_endpoint_private_access      = true

  # Control-plane audit logging, shipped to CloudWatch Logs.
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # Who can use the Kubernetes API (EKS access entries, not the old aws-auth ConfigMap).
  # 1. The identity that creates the cluster (HCP Terraform's run role) gets admin.
  enable_cluster_creator_admin_permissions = true

  # 2. Patricia's CloudLabs identity gets admin too, so kubectl works from the laptop.
  #    Without this the cluster exists but she is locked out of it.
  access_entries = {
    patricia = {
      principal_arn = var.admin_principal_arn

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    # 3. The GitHub Actions deploy role (github.tf): only "edit" inside the maraton
    #    namespace, enough to roll out a new image, not to change RBAC or other namespaces.
    github_deploy = {
      principal_arn = aws_iam_role.github_deploy.arn

      policy_associations = {
        edit_maraton = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = {
            type       = "namespace"
            namespaces = ["maraton"]
          }
        }
      }
    }
  }

  # Core add-ons managed by EKS (kept up to date by AWS rather than by hand).
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true # the network plugin must exist before nodes join
    }
    eks-pod-identity-agent = {}
  }

  # Managed node group: AWS handles the EC2 instances and their upgrades.
  # The module attaches AmazonEC2ContainerRegistryReadOnly so nodes can pull from ECR.
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
  }
}
