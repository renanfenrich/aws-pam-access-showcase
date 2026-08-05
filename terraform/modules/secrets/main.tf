locals {
  secret_keys = toset([
    "jumpserver-secret-key",
    "jumpserver-bootstrap-token",
    "jumpserver-admin-password",
    "jumpserver-demo-user-password",
    "jumpserver-postgres-password",
    "jumpserver-redis-password",
    "sensitive-resource-ssh-key",
    "openvpn-ca",
    "openvpn-demo-client-profile",
    "jumpserver-tls-ca",
    "jumpserver-tls-ca-certificate",
  ])
  openvpn_secret_keys = toset(["openvpn-ca", "openvpn-demo-client-profile"])
  jumpserver_secret_keys = toset([
    "jumpserver-secret-key",
    "jumpserver-bootstrap-token",
    "jumpserver-admin-password",
    "jumpserver-demo-user-password",
    "jumpserver-postgres-password",
    "jumpserver-redis-password",
    "sensitive-resource-ssh-key",
    "jumpserver-tls-ca",
  ])
}

resource "aws_kms_key" "secrets" {
  description             = "Showcase runtime secret encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_keys

  name                    = "${var.name}/${each.value}"
  description             = "Value is created outside Terraform by protected deployment automation."
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 7

  lifecycle {
    precondition {
      condition     = !can(regex("password|token|key", each.value)) || aws_kms_key.secrets.enable_key_rotation
      error_message = "Sensitive secret containers require a rotating customer-managed KMS key."
    }
  }
}

data "aws_iam_policy_document" "openvpn" {
  statement {
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
    resources = [for key in local.openvpn_secret_keys : aws_secretsmanager_secret.this[key].arn]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role_policy" "openvpn" {
  name   = "runtime-secrets"
  role   = var.openvpn_role_name
  policy = data.aws_iam_policy_document.openvpn.json
}

data "aws_iam_policy_document" "jumpserver" {
  statement {
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
    resources = [for key in local.jumpserver_secret_keys : aws_secretsmanager_secret.this[key].arn]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role_policy" "jumpserver" {
  name   = "runtime-secrets"
  role   = var.jumpserver_role_name
  policy = data.aws_iam_policy_document.jumpserver.json
}

data "aws_iam_policy_document" "resource" {
  for_each = aws_secretsmanager_secret.this

  statement {
    sid       = "DeploymentAutomation"
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
    resources = [each.value.arn]
    principals {
      type = "AWS"
      identifiers = compact(concat(
        [var.deployment_role_arn],
        contains(local.openvpn_secret_keys, each.key) ? [var.openvpn_role_arn] : [],
        contains(local.jumpserver_secret_keys, each.key) ? [var.jumpserver_role_arn] : [],
      ))
    }
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  for_each = aws_secretsmanager_secret.this

  secret_arn          = each.value.arn
  policy              = data.aws_iam_policy_document.resource[each.key].json
  block_public_policy = true
}
