data "aws_caller_identity" "current" {}

locals {
  name = "aws-pam-${var.name_suffix}"
  default_tags = {
    project     = "aws-pam-access-showcase"
    environment = "bootstrap"
    owner       = var.owner
    managed-by  = "terraform"
    expiration  = "none-bootstrap"
  }
  repository = "${var.github_owner}/${var.github_repository}"
  environments = {
    plan    = "showcase-plan"
    deploy  = "showcase-apply"
    destroy = "showcase-destroy"
  }
}

resource "aws_kms_key" "state" {
  description             = "Terraform state encryption for ${local.repository}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "state" {
  name          = "alias/${local.name}-terraform-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = "${local.name}-tfstate-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyUnencryptedObjectWrites"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.state.arn}/*"
        Condition = {
          StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" }
        }
      }
    ]
  })
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "github_trust" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.repository}:environment:${each.value}"]
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = local.environments

  name                 = "${local.name}-github-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust[each.key].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "ReadWriteStateAndLock"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/showcase/*"]
  }

  statement {
    sid = "UseStateKey"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:List*",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_policy" "state_access" {
  name   = "${local.name}-terraform-state"
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role_policy_attachment" "state_access" {
  for_each = { for name, role in aws_iam_role.github : name => role if name != "plan" }

  role       = each.value.name
  policy_arn = aws_iam_policy.state_access.arn
}

data "aws_iam_policy_document" "plan_state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/showcase/terraform.tfstate"]
  }

  statement {
    sid       = "ManageNativeLockfile"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/showcase/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "DecryptState"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "plan_state_access" {
  name   = "showcase-plan-state"
  role   = aws_iam_role.github["plan"].id
  policy = data.aws_iam_policy_document.plan_state_access.json
}

locals {
  workload_name                   = "aws-pam-${var.deployment_id}"
  transfer_bucket_arn             = "arn:aws:s3:::${local.workload_name}-ansible-${data.aws_caller_identity.current.account_id}"
  project_role_arn                = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-pam-*"
  project_profile_arn             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/aws-pam-*"
  project_key_arn                 = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
  project_alias_arn               = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws-pam-*"
  project_secret_arn              = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:aws-pam-*"
  project_log_group_arn           = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/aws-pam-*"
  project_topic_arn               = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:aws-pam-*"
  project_budget_arn              = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/${local.workload_name}-monthly"
  project_ec2_arn                 = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*/*"
  project_instance_arn            = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
  project_volume_arn              = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*"
  project_subnet_arn              = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/*"
  project_security_group_arn      = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*"
  project_security_group_rule_arn = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group-rule/*"
  project_elastic_ip_arn          = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:elastic-ip/*"
  project_flow_log_arn            = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"
  project_gateway_arn             = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:internet-gateway/*"
  project_nat_gateway_arn         = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:natgateway/*"
  project_route_table_arn         = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:route-table/*"
  project_vpc_endpoint_arn        = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc-endpoint/*"
  project_vpc_arn                 = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc/*"
  workload_role_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-pam-*-openvpn",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-pam-*-jumpserver",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-pam-*-sensitive-resource",
  ]
  request_tag_condition = {
    StringEquals = {
      "aws:RequestTag/project"     = "aws-pam-access-showcase"
      "aws:RequestTag/environment" = "showcase"
    }
    "ForAllValues:StringEquals" = {
      "aws:TagKeys" = ["project", "environment", "owner", "managed-by", "expiration", "deployment", "Name", "Role", "subnet-class"]
    }
  }
  resource_tag_condition = {
    StringEquals = {
      "aws:ResourceTag/project"     = "aws-pam-access-showcase"
      "aws:ResourceTag/environment" = "showcase"
    }
  }
  ec2_resource_tag_condition = {
    StringEquals = {
      "ec2:ResourceTag/project"     = "aws-pam-access-showcase"
      "ec2:ResourceTag/environment" = "showcase"
    }
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${local.name}-workload-boundary"
  description = "Maximum runtime permissions for showcase-created EC2 roles"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SystemsManagerAgent"
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
          "ssm:DescribeAssociation",
          "ssm:DescribeDocument",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:GetManifest",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:PutInventory",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
      {
        Sid      = "TransferBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = local.transfer_bucket_arn
      },
      {
        Sid      = "TransferObjects"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        Resource = "${local.transfer_bucket_arn}/*"
      },
      {
        Sid      = "RuntimeSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
        Resource = local.project_secret_arn
      },
      {
        Sid       = "ProjectKeyUse"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource  = local.project_key_arn
        Condition = local.resource_tag_condition
      },
      {
        Sid      = "ProjectHostLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = [local.project_log_group_arn, "${local.project_log_group_arn}:*"]
      },
      {
        Sid      = "CloudWatchAgentTelemetry"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData", "ec2:DescribeTags", "ec2:DescribeVolumes"]
        Resource = "*"
        Condition = {
          StringEqualsIfExists = { "cloudwatch:namespace" = "CWAgent" }
        }
      },
    ]
  })
}

locals {
  global_read_statement = {
    Sid    = "GlobalReadOnlyInventory"
    Effect = "Allow"
    Action = [
      "ec2:Describe*",
      "iam:List*",
      "kms:ListAliases",
      "logs:DescribeLogGroups",
      "tag:GetResources",
      "secretsmanager:ListSecrets",
      "sns:ListTopics",
      "ssm:DescribeInstanceInformation",
      "sts:GetCallerIdentity",
    ]
    Resource = "*"
  }
  project_read_statements = [
    local.global_read_statement,
    {
      Sid      = "ReadApprovedPublicParameter"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}::parameter/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    },
    {
      Sid      = "ReadProjectIdentity"
      Effect   = "Allow"
      Action   = ["iam:GetInstanceProfile", "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRolePolicies"]
      Resource = [local.project_role_arn, local.project_profile_arn]
    },
    {
      Sid       = "ReadProjectKeys"
      Effect    = "Allow"
      Action    = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListResourceTags"]
      Resource  = local.project_key_arn
      Condition = local.resource_tag_condition
    },
    {
      Sid      = "ReadProjectSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy", "secretsmanager:ListSecretVersionIds"]
      Resource = local.project_secret_arn
    },
    {
      Sid    = "ReadExactTransferBucket"
      Effect = "Allow"
      Action = [
        "s3:GetBucketAcl",
        "s3:GetBucketCors",
        "s3:GetBucketLocation",
        "s3:GetBucketLogging",
        "s3:GetBucketObjectLockConfiguration",
        "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketRequestPayment",
        "s3:GetBucketTagging",
        "s3:GetBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration",
        "s3:ListBucket",
      ]
      Resource = local.transfer_bucket_arn
    },
    {
      Sid      = "ReadProjectLogGroups"
      Effect   = "Allow"
      Action   = ["logs:ListTagsForResource"]
      Resource = [local.project_log_group_arn, "${local.project_log_group_arn}:*"]
    },
    {
      Sid      = "ReadProjectTopics"
      Effect   = "Allow"
      Action   = ["sns:GetSubscriptionAttributes", "sns:GetTopicAttributes", "sns:ListSubscriptionsByTopic", "sns:ListTagsForResource"]
      Resource = local.project_topic_arn
    },
    {
      Sid      = "ReadProjectBudget"
      Effect   = "Allow"
      Action   = ["budgets:ListTagsForResource", "budgets:ViewBudget"]
      Resource = local.project_budget_arn
    },
  ]
  plan_policy = jsonencode({ Version = "2012-10-17", Statement = local.project_read_statements })

  deploy_policy_documents = {
    iam = jsonencode({
      Version = "2012-10-17"
      Statement = concat(local.project_read_statements, [
        {
          Sid      = "CreateBoundedProjectRoles"
          Effect   = "Allow"
          Action   = ["iam:CreateRole"]
          Resource = local.project_role_arn
          Condition = merge(local.request_tag_condition, {
            StringEquals = merge(local.request_tag_condition.StringEquals, {
              "iam:PermissionsBoundary" = aws_iam_policy.workload_boundary.arn
            })
          })
        },
        {
          Sid      = "MaintainBoundary"
          Effect   = "Allow"
          Action   = ["iam:PutRolePermissionsBoundary"]
          Resource = local.project_role_arn
          Condition = {
            StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.workload_boundary.arn }
          }
        },
        {
          Sid      = "ManageProjectRoles"
          Effect   = "Allow"
          Action   = ["iam:DeleteRole", "iam:DeleteRolePermissionsBoundary", "iam:DeleteRolePolicy", "iam:PutRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy"]
          Resource = local.project_role_arn
        },
        {
          Sid       = "CreateProjectProfiles"
          Effect    = "Allow"
          Action    = ["iam:CreateInstanceProfile"]
          Resource  = local.project_profile_arn
          Condition = local.request_tag_condition
        },
        {
          Sid      = "ManageProjectProfiles"
          Effect   = "Allow"
          Action   = ["iam:AddRoleToInstanceProfile", "iam:DeleteInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile", "iam:UntagInstanceProfile"]
          Resource = [local.project_role_arn, local.project_profile_arn]
        },
        {
          Sid      = "AttachApprovedManagedPolicies"
          Effect   = "Allow"
          Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
          Resource = local.project_role_arn
          Condition = {
            ArnEquals = {
              "iam:PolicyARN" = [
                "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
                "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
              ]
            }
          }
        },
        {
          Sid      = "PassOnlyProjectInstanceRoles"
          Effect   = "Allow"
          Action   = ["iam:PassRole"]
          Resource = local.workload_role_arns
          Condition = {
            StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" }
          }
        },
      ])
    })
    ec2_create = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "CreateTaggedStandaloneEc2Resources"
          Effect = "Allow"
          Action = [
            "ec2:AllocateAddress",
            "ec2:CreateInternetGateway",
            "ec2:CreateVolume",
            "ec2:CreateVpc",
          ]
          Resource = [
            local.project_elastic_ip_arn,
            local.project_gateway_arn,
            local.project_volume_arn,
            local.project_vpc_arn,
          ]
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedSubnets"
          Effect    = "Allow"
          Action    = ["ec2:CreateSubnet"]
          Resource  = local.project_subnet_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedNatGateways"
          Effect    = "Allow"
          Action    = ["ec2:CreateNatGateway"]
          Resource  = local.project_nat_gateway_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedRouteTables"
          Effect    = "Allow"
          Action    = ["ec2:CreateRouteTable"]
          Resource  = local.project_route_table_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedSecurityGroups"
          Effect    = "Allow"
          Action    = ["ec2:CreateSecurityGroup"]
          Resource  = local.project_security_group_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedSecurityGroupRules"
          Effect    = "Allow"
          Action    = ["ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress"]
          Resource  = local.project_security_group_rule_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedVpcEndpoints"
          Effect    = "Allow"
          Action    = ["ec2:CreateVpcEndpoint"]
          Resource  = local.project_vpc_endpoint_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "CreateTaggedFlowLogs"
          Effect    = "Allow"
          Action    = ["ec2:CreateFlowLogs"]
          Resource  = local.project_flow_log_arn
          Condition = local.request_tag_condition
        },
        {
          Sid    = "UseOnlyProjectParentsForCreation"
          Effect = "Allow"
          Action = [
            "ec2:AuthorizeSecurityGroupEgress",
            "ec2:AuthorizeSecurityGroupIngress",
            "ec2:CreateFlowLogs",
            "ec2:CreateNatGateway",
            "ec2:CreateRouteTable",
            "ec2:CreateSecurityGroup",
            "ec2:CreateSubnet",
            "ec2:CreateVpcEndpoint",
          ]
          Resource = [
            local.project_elastic_ip_arn,
            local.project_route_table_arn,
            local.project_security_group_arn,
            local.project_subnet_arn,
            local.project_vpc_arn,
          ]
          Condition = local.ec2_resource_tag_condition
        },
        {
          Sid       = "LaunchTaggedInstancesAndVolumes"
          Effect    = "Allow"
          Action    = ["ec2:RunInstances"]
          Resource  = [local.project_instance_arn, local.project_volume_arn]
          Condition = local.request_tag_condition
        },
        {
          Sid    = "UseApprovedAmiAndImplicitNetworkInterfaces"
          Effect = "Allow"
          Action = ["ec2:RunInstances"]
          Resource = [
            "arn:aws:ec2:${var.aws_region}::image/*",
            "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
          ]
        },
        {
          Sid       = "LaunchIntoProjectNetwork"
          Effect    = "Allow"
          Action    = ["ec2:RunInstances"]
          Resource  = [local.project_subnet_arn, local.project_security_group_arn]
          Condition = local.ec2_resource_tag_condition
        },
        {
          Sid      = "TagResourcesDuringCreation"
          Effect   = "Allow"
          Action   = ["ec2:CreateTags"]
          Resource = local.project_ec2_arn
          Condition = {
            StringEquals = merge(local.request_tag_condition.StringEquals, {
              "ec2:CreateAction" = ["AllocateAddress", "AuthorizeSecurityGroupEgress", "AuthorizeSecurityGroupIngress", "CreateFlowLogs", "CreateInternetGateway", "CreateNatGateway", "CreateRouteTable", "CreateSecurityGroup", "CreateSubnet", "CreateVolume", "CreateVpc", "CreateVpcEndpoint", "RunInstances"]
            })
            "ForAllValues:StringEquals" = local.request_tag_condition["ForAllValues:StringEquals"]
          }
        },
      ]
    })
    ec2_manage = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.global_read_statement,
        {
          Sid      = "ManageTagsOnlyOnProjectResources"
          Effect   = "Allow"
          Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
          Resource = local.project_ec2_arn
          Condition = merge(local.ec2_resource_tag_condition, {
            "ForAllValues:StringEquals" = local.request_tag_condition["ForAllValues:StringEquals"]
          })
        },
        {
          Sid    = "MutateTaggedEc2Resources"
          Effect = "Allow"
          Action = [
            "ec2:AssociateAddress",
            "ec2:AssociateRouteTable",
            "ec2:AttachInternetGateway",
            "ec2:AttachVolume",
            "ec2:CreateRoute",
            "ec2:DeleteFlowLogs",
            "ec2:DeleteInternetGateway",
            "ec2:DeleteNatGateway",
            "ec2:DeleteRoute",
            "ec2:DeleteRouteTable",
            "ec2:DeleteSecurityGroup",
            "ec2:DeleteSubnet",
            "ec2:DeleteVolume",
            "ec2:DeleteVpc",
            "ec2:DeleteVpcEndpoints",
            "ec2:DetachInternetGateway",
            "ec2:DetachVolume",
            "ec2:DisassociateAddress",
            "ec2:DisassociateRouteTable",
            "ec2:ModifyInstanceAttribute",
            "ec2:ModifySubnetAttribute",
            "ec2:ModifyVpcAttribute",
            "ec2:ModifyVpcEndpoint",
            "ec2:ReleaseAddress",
            "ec2:ReplaceRoute",
            "ec2:RevokeSecurityGroupEgress",
            "ec2:RevokeSecurityGroupIngress",
            "ec2:TerminateInstances",
          ]
          Resource  = "*"
          Condition = local.ec2_resource_tag_condition
        },
      ]
    })
    storage = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ManageExactTransferBucket"
          Effect = "Allow"
          Action = [
            "s3:CreateBucket",
            "s3:DeleteBucket",
            "s3:DeleteBucketPolicy",
            "s3:GetBucketAcl",
            "s3:GetBucketLocation",
            "s3:GetBucketPolicy",
            "s3:GetBucketPublicAccessBlock",
            "s3:GetBucketTagging",
            "s3:GetBucketVersioning",
            "s3:GetEncryptionConfiguration",
            "s3:GetLifecycleConfiguration",
            "s3:ListBucket",
            "s3:ListBucketVersions",
            "s3:PutBucketPolicy",
            "s3:PutBucketPublicAccessBlock",
            "s3:PutBucketTagging",
            "s3:PutEncryptionConfiguration",
            "s3:PutLifecycleConfiguration",
          ]
          Resource = local.transfer_bucket_arn
        },
        {
          Sid      = "ManageExactTransferObjects"
          Effect   = "Allow"
          Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:GetObject", "s3:PutObject"]
          Resource = "${local.transfer_bucket_arn}/*"
        },
        {
          Sid       = "CreateTaggedProjectKeys"
          Effect    = "Allow"
          Action    = ["kms:CreateKey"]
          Resource  = "*"
          Condition = local.request_tag_condition
        },
        {
          Sid       = "ManageTaggedProjectKeys"
          Effect    = "Allow"
          Action    = ["kms:CancelKeyDeletion", "kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:DisableKey", "kms:EnableKey", "kms:EnableKeyRotation", "kms:Encrypt", "kms:GenerateDataKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListResourceTags", "kms:PutKeyPolicy", "kms:RetireGrant", "kms:RevokeGrant", "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource"]
          Resource  = local.project_key_arn
          Condition = local.resource_tag_condition
        },
        {
          Sid      = "ManageProjectAliasNames"
          Effect   = "Allow"
          Action   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
          Resource = local.project_alias_arn
        },
        {
          Sid       = "PointAliasesOnlyAtProjectKeys"
          Effect    = "Allow"
          Action    = ["kms:CreateAlias", "kms:UpdateAlias"]
          Resource  = local.project_key_arn
          Condition = local.resource_tag_condition
        },
      ]
    })
    services = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.global_read_statement,
        {
          Sid       = "CreateTaggedSecrets"
          Effect    = "Allow"
          Action    = ["secretsmanager:CreateSecret"]
          Resource  = local.project_secret_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "ManageTaggedSecrets"
          Effect    = "Allow"
          Action    = ["secretsmanager:DeleteResourcePolicy", "secretsmanager:DeleteSecret", "secretsmanager:GetResourcePolicy", "secretsmanager:GetSecretValue", "secretsmanager:PutResourcePolicy", "secretsmanager:PutSecretValue", "secretsmanager:RestoreSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource", "secretsmanager:UpdateSecret"]
          Resource  = local.project_secret_arn
          Condition = local.resource_tag_condition
        },
        {
          Sid       = "CreateTaggedLogGroups"
          Effect    = "Allow"
          Action    = ["logs:CreateLogGroup"]
          Resource  = local.project_log_group_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "ManageTaggedLogGroups"
          Effect    = "Allow"
          Action    = ["logs:DeleteLogGroup", "logs:ListTagsForResource", "logs:PutRetentionPolicy", "logs:TagResource", "logs:UntagResource"]
          Resource  = [local.project_log_group_arn, "${local.project_log_group_arn}:*"]
          Condition = local.resource_tag_condition
        },
        {
          Sid       = "CreateTaggedTopics"
          Effect    = "Allow"
          Action    = ["sns:CreateTopic"]
          Resource  = local.project_topic_arn
          Condition = local.request_tag_condition
        },
        {
          Sid       = "ManageTaggedTopics"
          Effect    = "Allow"
          Action    = ["sns:DeleteTopic", "sns:GetTopicAttributes", "sns:ListSubscriptionsByTopic", "sns:SetTopicAttributes", "sns:Subscribe", "sns:TagResource", "sns:Unsubscribe", "sns:UntagResource"]
          Resource  = local.project_topic_arn
          Condition = local.resource_tag_condition
        },
        {
          Sid      = "ManageExactBudget"
          Effect   = "Allow"
          Action   = ["budgets:ModifyBudget", "budgets:ViewBudget"]
          Resource = local.project_budget_arn
        },
        {
          Sid    = "UseApprovedSsmDocuments"
          Effect = "Allow"
          Action = ["ssm:SendCommand", "ssm:StartSession"]
          Resource = [
            "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
            "arn:aws:ssm:${var.aws_region}::document/AWS-StartNonInteractiveCommand",
            "arn:aws:ssm:${var.aws_region}::document/SSM-SessionManagerRunShell",
          ]
        },
        {
          Sid      = "ManageOnlyTaggedInstancesThroughSsm"
          Effect   = "Allow"
          Action   = ["ssm:SendCommand", "ssm:StartSession"]
          Resource = local.project_instance_arn
          Condition = {
            StringEquals = {
              "ssm:resourceTag/project"     = "aws-pam-access-showcase"
              "ssm:resourceTag/environment" = "showcase"
            }
          }
        },
        {
          Sid      = "ObserveAndCloseSsmExecutions"
          Effect   = "Allow"
          Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:ListCommands", "ssm:ResumeSession", "ssm:TerminateSession"]
          Resource = "*"
        },
      ]
    })
  }

  destroy_policy_documents = {
    iam = jsonencode({
      Version = "2012-10-17"
      Statement = concat(local.project_read_statements, [
        {
          Sid      = "RemoveOnlyProjectIdentity"
          Effect   = "Allow"
          Action   = ["iam:DeleteInstanceProfile", "iam:DeleteRole", "iam:DeleteRolePermissionsBoundary", "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:RemoveRoleFromInstanceProfile", "iam:UntagInstanceProfile", "iam:UntagRole"]
          Resource = [local.project_role_arn, local.project_profile_arn]
        },
      ])
    })
    ec2 = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.global_read_statement,
        {
          Sid    = "DeleteOnlyTaggedEc2Resources"
          Effect = "Allow"
          Action = [
            "ec2:DeleteFlowLogs",
            "ec2:DeleteInternetGateway",
            "ec2:DeleteNatGateway",
            "ec2:DeleteRoute",
            "ec2:DeleteRouteTable",
            "ec2:DeleteSecurityGroup",
            "ec2:DeleteSubnet",
            "ec2:DeleteTags",
            "ec2:DeleteVolume",
            "ec2:DeleteVpc",
            "ec2:DeleteVpcEndpoints",
            "ec2:DetachInternetGateway",
            "ec2:DetachVolume",
            "ec2:DisassociateAddress",
            "ec2:DisassociateRouteTable",
            "ec2:ReleaseAddress",
            "ec2:RevokeSecurityGroupEgress",
            "ec2:RevokeSecurityGroupIngress",
            "ec2:TerminateInstances",
          ]
          Resource  = "*"
          Condition = local.ec2_resource_tag_condition
        },
      ]
    })
    storage = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "DeleteExactTransferBucket"
          Effect   = "Allow"
          Action   = ["s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:GetBucketLocation", "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetBucketTagging", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:ListBucket", "s3:ListBucketVersions"]
          Resource = local.transfer_bucket_arn
        },
        {
          Sid      = "DeleteExactTransferObjects"
          Effect   = "Allow"
          Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:GetObject"]
          Resource = "${local.transfer_bucket_arn}/*"
        },
        {
          Sid       = "ScheduleTaggedProjectKeys"
          Effect    = "Allow"
          Action    = ["kms:DescribeKey", "kms:DisableKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListGrants", "kms:ListResourceTags", "kms:ScheduleKeyDeletion"]
          Resource  = local.project_key_arn
          Condition = local.resource_tag_condition
        },
        {
          Sid      = "DeleteProjectAliases"
          Effect   = "Allow"
          Action   = ["kms:DeleteAlias"]
          Resource = local.project_alias_arn
        },
      ]
    })
    services = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.global_read_statement,
        {
          Sid      = "RevokeVpnThroughApprovedDocument"
          Effect   = "Allow"
          Action   = ["ssm:SendCommand"]
          Resource = "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"
        },
        {
          Sid      = "RevokeVpnOnTaggedInstances"
          Effect   = "Allow"
          Action   = ["ssm:SendCommand"]
          Resource = local.project_instance_arn
          Condition = {
            StringEquals = {
              "ssm:resourceTag/project"     = "aws-pam-access-showcase"
              "ssm:resourceTag/environment" = "showcase"
            }
          }
        },
        {
          Sid      = "ObserveRevocation"
          Effect   = "Allow"
          Action   = ["ssm:GetCommandInvocation"]
          Resource = "*"
        },
        {
          Sid       = "DeleteTaggedSecrets"
          Effect    = "Allow"
          Action    = ["secretsmanager:DeleteResourcePolicy", "secretsmanager:DeleteSecret"]
          Resource  = local.project_secret_arn
          Condition = local.resource_tag_condition
        },
        {
          Sid       = "DeleteTaggedLogGroups"
          Effect    = "Allow"
          Action    = ["logs:DeleteLogGroup"]
          Resource  = [local.project_log_group_arn, "${local.project_log_group_arn}:*"]
          Condition = local.resource_tag_condition
        },
        {
          Sid       = "DeleteTaggedTopics"
          Effect    = "Allow"
          Action    = ["sns:DeleteTopic", "sns:Unsubscribe"]
          Resource  = local.project_topic_arn
          Condition = local.resource_tag_condition
        },
        {
          Sid      = "DeleteExactBudget"
          Effect   = "Allow"
          Action   = ["budgets:ModifyBudget"]
          Resource = local.project_budget_arn
        },
      ]
    })
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "showcase-plan"
  role   = aws_iam_role.github["plan"].id
  policy = local.plan_policy
}

resource "aws_iam_policy" "deploy" {
  for_each = local.deploy_policy_documents

  name   = "${local.name}-deploy-${each.key}"
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each = aws_iam_policy.deploy

  role       = aws_iam_role.github["deploy"].name
  policy_arn = each.value.arn
}

resource "aws_iam_policy" "destroy" {
  for_each = local.destroy_policy_documents

  name   = "${local.name}-destroy-${each.key}"
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "destroy" {
  for_each = aws_iam_policy.destroy

  role       = aws_iam_role.github["destroy"].name
  policy_arn = each.value.arn
}

check "oidc_subjects_are_environment_scoped" {
  assert {
    condition     = alltrue([for environment in values(local.environments) : startswith(environment, "showcase-")])
    error_message = "All OIDC subjects must use a dedicated showcase environment."
  }
}
