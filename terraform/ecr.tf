# -----------------------------------------------------------------------------
# ECR: private registry for the Maratón container image.
#   - scan_on_push: every pushed image gets a vulnerability scan (basic scanning).
#   - IMMUTABLE tags: a tag (e.g. a git commit SHA) can never be overwritten, so
#     what was scanned is exactly what gets deployed.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Lab only: lets `terraform destroy` delete the repo even if it still holds images.
  force_delete = true
}

# Keep the registry tidy: only the 10 most recent images are kept.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
