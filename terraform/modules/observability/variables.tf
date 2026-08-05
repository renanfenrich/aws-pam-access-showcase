variable "name" { type = string }
variable "vpc_id" { type = string }
variable "monthly_budget_usd" { type = number }
variable "budget_email" {
  type    = string
  default = ""
}
variable "flow_log_bucket_arn" { type = string }
