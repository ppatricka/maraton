# -----------------------------------------------------------------------------
# Backup bucket for the daily mongodump.
# INTENTIONAL WEAKNESS (required by the exercise): anyone on the internet can
# list the bucket and download every backup.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "backups" {
  # Bucket names are global, so the account ID keeps this one unique.
  bucket = "${var.project}-db-backups-${data.aws_caller_identity.current.account_id}"

  # Lab only: lets `terraform destroy` delete the bucket even when it holds backups.
  force_destroy = true
}

# Turn OFF the bucket-level public access block, otherwise AWS rejects the public policy.
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "backups_public" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicList"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.backups.arn
      },
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backups.arn}/*"
      },
    ]
  })

  # The policy can only be attached after the public access block is lifted.
  depends_on = [aws_s3_bucket_public_access_block.backups]
}
