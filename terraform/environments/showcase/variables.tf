variable "deployment_enabled" {
  description = "Safety interlock. Must be explicitly true for any plan or apply."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region for the ephemeral showcase."
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier."
  }
}

variable "deployment_id" {
  description = "Deterministic lowercase deployment suffix."
  type        = string
  default     = "demo"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.deployment_id))
    error_message = "deployment_id must contain 3-16 lowercase letters, numbers, or hyphens."
  }
}

variable "operator_cidr" {
  description = "Single operator public CIDR allowed to reach UDP 1194; empty is safe and cannot deploy."
  type        = string
  default     = ""
  validation {
    condition     = var.operator_cidr == "" || can(cidrhost(var.operator_cidr, 0))
    error_message = "operator_cidr must be empty or a valid CIDR."
  }
}

variable "vpn_client_cidr" {
  description = "OpenVPN client address pool."
  type        = string
  default     = "10.250.0.0/24"
}

variable "authorization_expiration" {
  description = "RFC3339 expiration applied to the single JumpServer authorization."
  type        = string
  default     = ""
  validation {
    condition     = var.authorization_expiration == "" || can(timecmp(var.authorization_expiration, "2020-01-01T00:00:00Z"))
    error_message = "authorization_expiration must be an RFC3339 timestamp."
  }
}

variable "expiration" {
  description = "YYYY-MM-DD resource expiration tag for this ephemeral deployment."
  type        = string
  default     = ""
  validation {
    condition     = var.expiration == "" || can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.expiration))
    error_message = "expiration must be YYYY-MM-DD."
  }
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "platform-security"
}

variable "deployment_role_arn" {
  description = "Bootstrap-created GitHub deployment role allowed to use the Ansible transfer bucket and secrets."
  type        = string
  default     = ""
}

variable "jumpserver_instance_type" {
  description = "At least 4 vCPU and 8 GiB; t3.xlarge provides 4 vCPU and 16 GiB."
  type        = string
  default     = "t3.xlarge"
}

variable "openvpn_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "sensitive_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "monthly_budget_usd" {
  type    = number
  default = 250
  validation {
    condition     = var.monthly_budget_usd >= 10
    error_message = "monthly_budget_usd must be at least USD 10."
  }
}

variable "budget_email" {
  description = "Optional email subscriber for budget notifications."
  type        = string
  default     = ""
}
