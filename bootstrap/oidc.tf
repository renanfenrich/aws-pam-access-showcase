variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider; set false when it already exists."
  type        = bool
  default     = true
}

