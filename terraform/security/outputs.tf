output "audit_bucket" {
  description = "Private bucket holding CloudTrail logs and AWS Config snapshots"
  value       = aws_s3_bucket.audit.bucket
}

output "cloudtrail_name" {
  description = "Multi-region trail"
  value       = aws_cloudtrail.main.name
}

output "guardduty_detector_id" {
  description = "For aws guardduty list-findings / create-sample-findings"
  value       = aws_guardduty_detector.main.id
}
