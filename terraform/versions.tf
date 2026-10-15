terraform {
  required_version = ">= 1.6.0"

  # State, runs and AWS credentials are all managed by HCP Terraform.
  # Organization: patriciarojas-sandbox.
  cloud {
    organization = "patriciarojas-sandbox"

    workspaces {
      name = "maraton-aws"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
