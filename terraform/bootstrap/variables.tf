variable "aws_region" {
  description = "AWS region for the provider (IAM itself is global)"
  type        = string
  default     = "us-east-1"
}

variable "hcp_terraform_hostname" {
  description = "HCP Terraform hostname"
  type        = string
  default     = "app.terraform.io"
}

variable "hcp_organization" {
  description = "Your HCP Terraform organization name (exactly as shown in the HCP Terraform UI)"
  type        = string
  default     = "patriciarojas-sandbox"
}

variable "hcp_project" {
  description = "HCP Terraform project that holds the workspace"
  type        = string
  default     = "wiz"
}

variable "hcp_workspaces" {
  description = "HCP Terraform workspaces whose runs may assume the role (app environment + security baseline)"
  type        = list(string)
  default     = ["maraton-aws", "maraton-security"]
}
