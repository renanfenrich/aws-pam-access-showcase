data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  for_each = toset(["openvpn", "jumpserver", "sensitive-resource"])

  name                 = "${var.name}-${each.value}"
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each = aws_iam_role.instance

  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  for_each = aws_iam_role.instance

  name = each.value.name
  role = each.value.name
}

data "aws_iam_policy_document" "transfer_key" {
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
    sid = "FlowLogEncryption"
    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "transfer" {
  description             = "Ansible SSM transfer object encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.transfer_key.json
}

resource "aws_kms_alias" "transfer" {
  name          = "alias/${var.name}-ansible-transfer"
  target_key_id = aws_kms_key.transfer.key_id
}

resource "aws_s3_bucket" "transfer" {
  bucket        = "${var.name}-ansible-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.transfer.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id

  rule {
    id     = "expire-temporary-objects"
    status = "Enabled"
    filter {}
    expiration { days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

locals {
  approved_principals = concat([var.deployment_role_arn], [for role in aws_iam_role.instance : role.arn])
}

data "aws_iam_policy_document" "transfer_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.transfer.arn, "${aws_s3_bucket.transfer.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyUnapprovedPrincipals"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.transfer.arn, "${aws_s3_bucket.transfer.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.approved_principals
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalServiceName"
      values   = ["delivery.logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowFlowLogBucketAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.transfer.arn]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid       = "AllowFlowLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.transfer.arn}/vpc-flow-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "transfer" {
  bucket = aws_s3_bucket.transfer.id
  policy = data.aws_iam_policy_document.transfer_bucket.json
}

data "aws_iam_policy_document" "transfer_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.transfer.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.transfer.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.transfer.arn]
  }
}

resource "aws_iam_role_policy" "transfer_access" {
  for_each = aws_iam_role.instance

  name   = "ansible-ssm-transfer"
  role   = each.value.id
  policy = data.aws_iam_policy_document.transfer_access.json
}
