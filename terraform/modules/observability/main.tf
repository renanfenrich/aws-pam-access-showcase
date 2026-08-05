resource "aws_cloudwatch_log_group" "host" {
  for_each = toset(["openvpn", "jumpserver", "sensitive-resource"])

  name              = "/aws/${var.name}/${each.value}"
  retention_in_days = 14
}

resource "aws_flow_log" "this" {
  log_destination      = "${var.flow_log_bucket_arn}/vpc-flow-logs/"
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = var.vpc_id
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "budget_kms" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "BudgetNotifications"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "sns.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "budget" {
  description             = "Budget notification encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.budget_kms.json
}

resource "aws_kms_alias" "budget" {
  name          = "alias/${var.name}-budget-alerts"
  target_key_id = aws_kms_key.budget.key_id
}

resource "aws_sns_topic" "budget" {
  name              = "${var.name}-budget-alerts"
  kms_master_key_id = aws_kms_key.budget.arn
}

data "aws_iam_policy_document" "budget_topic" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.budget.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "budget" {
  arn    = aws_sns_topic.budget.arn
  policy = data.aws_iam_policy_document.budget_topic.json
}

resource "aws_sns_topic_subscription" "budget_email" {
  count = var.budget_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.budget.arn
  protocol  = "email"
  endpoint  = var.budget_email
}

resource "aws_budgets_budget" "this" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$aws-pam-access-showcase"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.budget.arn]
  }
}
