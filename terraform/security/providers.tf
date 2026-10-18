# Same pattern as the app workspace: HCP Terraform injects short-lived AWS
# credentials through OIDC (TFC_AWS_PROVIDER_AUTH), no keys here.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Owner       = var.owner
      Environment = "exercise"
      ManagedBy   = "hcp-terraform"
      Purpose     = "wiz-technical-exercise"
      Component   = "security-baseline"
    }
  }

  ignore_tags {
    keys = ["aws-apn-id"] # added by the lab platform outside Terraform
  }
}

data "aws_caller_identity" "current" {}
