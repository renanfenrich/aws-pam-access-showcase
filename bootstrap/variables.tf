variable "aws_region" {
  description = "AWS region used for the bootstrap resources."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier."
  }
}

variable "github_owner" {
  description = "Exact GitHub repository owner used in OIDC subject conditions."
  type        = string
  default     = "renanfenrich"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_owner))
    error_message = "github_owner contains unsupported characters."
  }
}

variable "github_repository" {
  description = "Exact GitHub repository name used in OIDC subject conditions."
  type        = string
  default     = "aws-pam-access-showcase"
}

variable "github_oidc_subject_prefix" {
  description = "Optional exact repository prefix from GitHub's OIDC customization endpoint; defaults to repo:<owner>/<repository>."
  type        = string
  default     = ""

  validation {
    condition     = var.github_oidc_subject_prefix == "" || can(regex("^repo:[^:]+$", var.github_oidc_subject_prefix))
    error_message = "github_oidc_subject_prefix must be empty or an exact repo-scoped subject prefix."
  }
}

variable "name_suffix" {
  description = "Lowercase suffix that makes global names unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.name_suffix))
    error_message = "name_suffix must be 4-12 lowercase alphanumeric characters."
  }
}

variable "deployment_id" {
  description = "Deployment identifier used to scope workload names and the Ansible transfer bucket."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.deployment_id))
    error_message = "deployment_id must contain 3-16 lowercase letters, numbers, or hyphens."
  }
}

variable "owner" {
  description = "Owner tag for cost and operational attribution."
  type        = string
  default     = "platform-security"
}
