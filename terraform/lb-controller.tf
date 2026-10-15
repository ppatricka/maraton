# -----------------------------------------------------------------------------
# AWS identity for the AWS Load Balancer Controller.
#
# The controller runs as pods in kube-system. When it sees a Kubernetes Ingress,
# it creates an Application Load Balancer (ALB) in AWS, so it needs AWS permissions.
# EKS Pod Identity hands those permissions to ONLY the controller's service
# account: the pods get short-lived credentials for this role, not the node's role.
#
# The controller itself is installed with Helm from the laptop (see k8s/README.md),
# because HCP Terraform's runners can't reach the IP-restricted cluster API.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lb_controller" {
  name = "${var.project}-aws-load-balancer-controller"

  # Only the EKS Pod Identity service may assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Official policy published with the controller release (policies/ holds a copy of
# docs/install/iam_policy.json from the v3.6.0 tag). Keep it in step with the Helm chart version.
resource "aws_iam_policy" "lb_controller" {
  name   = "${var.project}-aws-load-balancer-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller-v3.6.0.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# Binds the role to the service account the Helm chart creates:
# namespace kube-system, name aws-load-balancer-controller.
resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}
