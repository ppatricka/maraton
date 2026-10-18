# -----------------------------------------------------------------------------
# One-time bootstrap: lets HCP Terraform authenticate to AWS WITHOUT static keys.
#
# Creates an OIDC trust between your AWS account and HCP Terraform
# (app.terraform.io). Each HCP Terraform run gets a short-lived token that it
# exchanges for temporary AWS credentials by assuming the role below.
# Run this once from your laptop with your CloudLabs AWS credentials.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "patriciarojas-sandbox"

    workspaces {
      name = "maraton-bootstrap"
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
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "maraton"
      ManagedBy = "terraform-bootstrap"
      Purpose   = "wiz-technical-exercise"
    }
  }
}

data "tls_certificate" "hcp_terraform" {
  url = "https://${var.hcp_terraform_hostname}"
}

resource "aws_iam_openid_connect_provider" "hcp_terraform" {
  url             = "https://${var.hcp_terraform_hostname}"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.hcp_terraform.certificates[0].sha1_fingerprint]
}

# Only runs from YOUR organization, project and listed workspaces may assume the role.
data "aws_iam_policy_document" "hcp_terraform_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp_terraform.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.hcp_terraform_hostname}:aud"
      values   = ["aws.workload.identity"]
    }

    condition {
      test     = "StringLike"
      variable = "${var.hcp_terraform_hostname}:sub"
      values = [
        for ws in var.hcp_workspaces :
        "organization:${var.hcp_organization}:project:${var.hcp_project}:workspace:${ws}:run_phase:*"
      ]
    }
  }
}

resource "aws_iam_role" "hcp_terraform_run" {
  name                 = "maraton-hcp-terraform-run"
  description          = "Assumed by HCP Terraform runs for the ${join(", ", var.hcp_workspaces)} workspaces"
  assume_role_policy   = data.aws_iam_policy_document.hcp_terraform_trust.json
  max_session_duration = 3600
}

# The exercise creates IAM roles, EKS, EC2, S3 and security services, so the run
# role needs broad rights. In a real environment you would scope this down;
# call this out as a deliberate lab trade-off in the presentation.
resource "aws_iam_role_policy_attachment" "hcp_terraform_admin" {
  role       = aws_iam_role.hcp_terraform_run.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
