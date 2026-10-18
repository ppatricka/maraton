# -----------------------------------------------------------------------------
# DETECTIVE cloud controls: native AWS tools that find the environment's
# misconfigurations, vulnerabilities and suspicious activity.
#
#   AWS Config + Security Hub -> misconfigurations (public bucket, open SSH, ...)
#   Amazon Inspector          -> vulnerabilities (outdated OS packages, image CVEs)
#   GuardDuty                 -> threats (e.g. stolen instance credentials used
#                                outside AWS, suspicious Kubernetes API activity)
# -----------------------------------------------------------------------------

# --- AWS Config: records every resource's configuration and evaluates rules ---

resource "aws_iam_role" "config" {
  name = "${var.project}-aws-config"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true # IAM roles/policies (record once, in this region)
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.audit.id
  s3_key_prefix  = "config"

  depends_on = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.audit]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# Three rules that map directly to required weaknesses, so they're easy to show in
# the Config console. Security Hub (below) adds many more of its own.
locals {
  config_rules = {
    "s3-bucket-public-read-prohibited" = "S3_BUCKET_PUBLIC_READ_PROHIBITED" # backup bucket
    "restricted-ssh"                   = "INCOMING_SSH_DISABLED"            # MongoDB VM
    "eks-endpoint-no-public-access"    = "EKS_ENDPOINT_NO_PUBLIC_ACCESS"    # EKS API
  }
}

resource "aws_config_config_rule" "managed" {
  for_each = local.config_rules

  name = "${var.project}-${each.key}"
  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# --- Security Hub: one dashboard, scored against AWS best practices -----------

resource "aws_securityhub_account" "main" {
  enable_default_standards = false # subscribe explicitly below
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  # Security Hub evaluates its controls through AWS Config, so Config must be recording.
  depends_on = [aws_securityhub_account.main, aws_config_configuration_recorder_status.main]
}

# --- Amazon Inspector: vulnerability scanning for EC2 and ECR ------------------
# EC2 scanning uses the SSM agent (preinstalled on Ubuntu AMIs); the MongoDB VM
# role gets AmazonSSMManagedInstanceCore for that in the app workspace (../mongodb.tf).

resource "aws_inspector2_enabler" "main" {
  account_ids    = [local.account_id]
  resource_types = ["EC2", "ECR"]
}

# --- GuardDuty: threat detection from CloudTrail, VPC flow, DNS, S3 and EKS logs

resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES" # fastest export to Security Hub/EventBridge
}

resource "aws_guardduty_detector_feature" "s3" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "eks_audit" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}
