# -----------------------------------------------------------------------------
# Network: one VPC across two availability zones.
#   Public subnets  -> internet-facing load balancer, NAT gateway, MongoDB VM
#   Private subnets -> EKS worker nodes (no public IPs; outbound via NAT)
# -----------------------------------------------------------------------------

locals {
  cluster_name = "${var.project}-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  # One NAT gateway keeps lab costs down. Production would use one per AZ.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Tags the AWS Load Balancer Controller uses to discover where to place
  # internet-facing (public) and internal load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}
