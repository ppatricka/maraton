# No credentials here: HCP Terraform injects short-lived AWS credentials into
# each run through dynamic provider credentials (TFC_AWS_PROVIDER_AUTH).
provider "aws" {
  region = var.aws_region

  # Every resource gets these tags, which makes the environment easy to find
  # (and easy to scope in security tools) during the demo.
  default_tags {
    tags = {
      Project     = var.project
      Owner       = var.owner
      Environment = "exercise"
      ManagedBy   = "hcp-terraform"
      Purpose     = "wiz-technical-exercise"
    }
  }

  # The lab platform adds an "aws-apn-id" tag to some resources outside Terraform.
  # Ignore it so plans don't keep trying to remove it (tag drift we don't own).
  ignore_tags {
    keys = ["aws-apn-id"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
