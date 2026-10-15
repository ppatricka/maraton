output "hcp_terraform_run_role_arn" {
  description = "Paste this into the workspace variable TFC_AWS_RUN_ROLE_ARN"
  value       = aws_iam_role.hcp_terraform_run.arn
}
