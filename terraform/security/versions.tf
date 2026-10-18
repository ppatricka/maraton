terraform {
  required_version = ">= 1.6.0"

  # Separate HCP Terraform workspace for the security baseline, so it has its own
  # state, runs and lifecycle: the app environment (../, workspace maraton-aws) can be
  # destroyed and rebuilt while audit logging and detection keep running.
  cloud {
    organization = "patriciarojas-sandbox"

    workspaces {
      name = "maraton-security"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}
