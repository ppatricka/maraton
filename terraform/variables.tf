variable "aws_region" {
  description = "AWS region for the whole environment"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used to prefix resources"
  type        = string
  default     = "maraton"
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
  default     = "patricia"
}

variable "vpc_cidr" {
  description = "Address range for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnets (load balancer, NAT gateway, MongoDB VM), one per AZ"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnets (EKS worker nodes), one per AZ"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (pick one in standard support: aws eks describe-cluster-versions)"
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = "EC2 instance type for the EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "admin_principal_arn" {
  description = "IAM user or role ARN of Patricia's CloudLabs identity, granted cluster admin. Set in the HCP workspace."
  type        = string
}

variable "mongodb_instance_type" {
  description = "EC2 instance type for the MongoDB VM"
  type        = string
  default     = "t3.small"
}

variable "ssh_public_key" {
  description = "SSH public key for the MongoDB VM (contents of ~/.ssh/id_rsa.pub). Set in the HCP workspace."
  type        = string
}

variable "github_repository" {
  description = "GitHub repo (owner/name) whose main branch may deploy the app"
  type        = string
  default     = "ppatricka/maraton"
}
