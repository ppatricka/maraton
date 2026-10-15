output "vpc_id" {
  description = "ID of the exercise VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets (load balancer, NAT, MongoDB VM)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnets (EKS worker nodes)"
  value       = module.vpc.private_subnets
}

output "availability_zones" {
  description = "AZs the environment spans"
  value       = local.azs
}

output "cluster_name" {
  description = "EKS cluster name (for aws eks update-kubeconfig)"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "Where the CI pipeline pushes the app image"
  value       = aws_ecr_repository.app.repository_url
}

output "kubeconfig_command" {
  description = "Run this on the laptop to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "mongodb_public_ip" {
  description = "Public IP of the MongoDB VM (SSH only; MongoDB itself isn't reachable from here)"
  value       = aws_instance.mongodb.public_ip
}

output "mongodb_private_ip" {
  description = "Private IP the app uses to reach MongoDB"
  value       = aws_instance.mongodb.private_ip
}

output "ssh_command" {
  description = "SSH into the MongoDB VM"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.mongodb.public_ip}"
}

output "backup_bucket" {
  description = "S3 bucket holding the daily MongoDB backups (publicly listable and readable)"
  value       = aws_s3_bucket.backups.bucket
}

output "backup_bucket_public_url" {
  description = "Open in a browser with no login to see the public listing"
  value       = "https://${aws_s3_bucket.backups.bucket}.s3.amazonaws.com/"
}

output "mongodb_uri" {
  description = "Connection string for the app (goes into a Kubernetes Secret in step 6)"
  value       = "mongodb://${var.project}:${random_password.mongo_app.result}@${aws_instance.mongodb.private_ip}:27017/${var.project}?authSource=${var.project}"
  sensitive   = true
}

output "lb_controller_helm_command" {
  description = "Installs the AWS Load Balancer Controller (run from the laptop after helm repo add eks https://aws.github.io/eks-charts)"
  value       = "helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller --version 3.6.0 -n kube-system --set clusterName=${module.eks.cluster_name} --set serviceAccount.name=aws-load-balancer-controller --set region=${var.aws_region} --set vpcId=${module.vpc.vpc_id}"
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN variable in the GitHub repo"
  value       = aws_iam_role.github_deploy.arn
}
