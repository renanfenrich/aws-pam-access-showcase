output "state_bucket" {
  description = "S3 bucket for the main stack backend."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "KMS key used by the main stack backend."
  value       = aws_kms_key.state.arn
}

output "github_role_arns" {
  description = "Environment-scoped GitHub Actions role ARNs."
  value       = { for name, role in aws_iam_role.github : name => role.arn }
}

output "backend_config" {
  description = "Values used to initialize the main stack with native S3 lockfiles."
  value = {
    bucket       = aws_s3_bucket.state.id
    key          = "showcase/terraform.tfstate"
    region       = var.aws_region
    encrypt      = true
    kms_key_id   = aws_kms_key.state.arn
    use_lockfile = true
  }
}

