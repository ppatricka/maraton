# -----------------------------------------------------------------------------
# Control-plane audit logging (exercise requirement) + a PREVENTIVE cloud control.
#
#   - CloudTrail: every AWS API call in every region, plus S3 data events for the
#     backup bucket (so anonymous downloads of the public backups are recorded).
#   - The log bucket is the opposite of the backup bucket: S3 Block Public Access
#     is fully ON (preventive: AWS refuses any attempt to make it public, even by
#     an admin), and deleting logs is denied to everyone except the IaC run role
#     (attackers usually delete logs to hide their tracks).
#   - AWS Config (detective.tf) delivers its snapshots to the same bucket.
# EKS control-plane audit logs are on in the app workspace (../eks.tf, CloudWatch Logs).
# -----------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id
  # The app workspace's backup bucket, referenced by naming convention (not by reading
  # that workspace's state) so this workspace keeps working while the app is destroyed.
  backup_bucket_arn = "arn:aws:s3:::${var.project}-db-backups-${data.aws_caller_identity.current.account_id}"
  audit_bucket      = "${var.project}-audit-logs-${local.account_id}"
  trail_name        = "${var.project}-trail"
  trail_arn         = "arn:aws:cloudtrail:${var.aws_region}:${local.account_id}:trail/${local.trail_name}"
  hcp_run_role_arn  = "arn:aws:iam::${local.account_id}:role/maraton-hcp-terraform-run"
}

resource "aws_s3_bucket" "audit" {
  bucket = local.audit_bucket

  # Lab only, so `terraform destroy` can clean up. The deny-delete policy below
  # still allows the HCP Terraform run role, which is what performs the destroy.
  force_destroy = true
}

# PREVENTIVE CONTROL: all four Block Public Access settings on. Any public ACL or
# public bucket policy is rejected by S3 itself. Compare with backups.tf.
resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Versioning keeps overwritten log files recoverable.
resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "audit_bucket" {
  # CloudTrail may check the bucket and write log files, only for this trail.
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.audit.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit.arn}/cloudtrail/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # AWS Config may check the bucket and write configuration snapshots.
  statement {
    sid       = "ConfigAclCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.audit.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit.arn}/config/AWSLogs/${local.account_id}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # PREVENTIVE: nobody may delete log files or the bucket, except the HCP Terraform
  # run role (break-glass for `terraform destroy`). Applies to admins too.
  statement {
    sid       = "DenyLogDeletion"
    effect    = "Deny"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:DeleteBucket"]
    resources = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.hcp_run_role_arn]
    }
  }

  # Logs only travel over TLS.
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket     = aws_s3_bucket.audit.id
  policy     = data.aws_iam_policy_document.audit_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.audit]
}

# Customer-managed KMS key for the CloudTrail log files: reading logs needs both S3
# access AND permission to use this key, and every key use is itself logged.
resource "aws_kms_key" "cloudtrail" {
  description             = "Encrypts ${local.trail_name} log files"
  enable_key_rotation     = true
  deletion_window_in_days = 7 # lab: shortest allowed

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Standard statement: lets IAM policies in this account manage and use the key.
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${local.account_id}:trail/*" }
        }
      },
      {
        Sid       = "CloudTrailDescribe"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/${local.trail_name}"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.audit.id
  s3_key_prefix  = "cloudtrail"

  is_multi_region_trail         = true # API calls in every region, not just us-east-1
  include_global_service_events = true # IAM, STS and other global services
  enable_log_file_validation    = true # signed digest files prove logs weren't altered
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  # Management events (every control-plane API call) ...
  advanced_event_selector {
    name = "All management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # ... plus object-level (data) events on the public backup bucket, so every
  # download of a backup, including anonymous ones, is recorded.
  advanced_event_selector {
    name = "Backup bucket object access"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = ["${local.backup_bucket_arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.audit]
}
