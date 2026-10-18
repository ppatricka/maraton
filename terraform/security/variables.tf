variable "aws_region" {
  description = "AWS region for the security baseline (same as the app environment)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used to prefix resources"
  type        = string
  default     = "maraton"
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
  default     = "patricia"
}
