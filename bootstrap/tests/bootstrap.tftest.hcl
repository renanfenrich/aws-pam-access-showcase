mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    override_during = plan
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/aws-pam-test-workload-boundary"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:GetCallerIdentity\",\"Resource\":\"*\"}]}"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      user_id    = "AIDATEST"
    }
  }
}

run "environment_scoped_roles" {
  command = plan

  variables {
    name_suffix                = "test1234"
    github_oidc_subject_prefix = "repo:renanfenrich@1413054/aws-pam-access-showcase@1324241869"
  }

  assert {
    condition     = length(aws_iam_role.github) == 3
    error_message = "The bootstrap must create separate plan, deploy, and destroy roles."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "Terraform state versioning must remain enabled."
  }

  assert {
    condition     = local.oidc_subject_prefix == "repo:renanfenrich@1413054/aws-pam-access-showcase@1324241869"
    error_message = "The configured stable-ID repository subject prefix must be used exactly."
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.plan_state_access.statement[3].actions, "kms:GenerateDataKey")
    error_message = "The plan role must be able to encrypt its native S3 lockfile."
  }
}

run "least_privilege_policy_regressions" {
  command = plan

  variables {
    name_suffix   = "test1234"
    deployment_id = "demo"
  }

  assert {
    condition = alltrue(flatten([
      for policy in values(aws_iam_policy.deploy) : [
        for statement in jsondecode(policy.policy).Statement :
        alltrue([for resource in flatten([statement.Resource]) : resource != "*"])
        if contains(flatten([statement.Action]), "iam:PassRole")
      ]
    ]))
    error_message = "iam:PassRole must never target all resources."
  }

  assert {
    condition = alltrue([
      for action in flatten([
        for policy in values(aws_iam_policy.destroy) : flatten([
          for statement in jsondecode(policy.policy).Statement : flatten([statement.Action])
        ])
      ]) :
      length(regexall("(?i)^[^:]+:create", action)) == 0 &&
      !contains([
        "ec2:runinstances",
        "iam:attachrolepolicy",
        "iam:putrolepolicy",
        "secretsmanager:putsecretvalue",
        "kms:enablekey",
      ], lower(action))
    ])
    error_message = "The destroy role must not contain create or privilege-expanding actions."
  }

  assert {
    condition = alltrue(flatten([
      for policy in values(aws_iam_policy.deploy) : [
        for statement in jsondecode(policy.policy).Statement :
        alltrue([
          for resource in flatten([statement.Resource]) :
          startswith(resource, "arn:aws:iam::") && strcontains(resource, "aws-pam-")
        ])
        if anytrue([
          for action in flatten([statement.Action]) :
          length(regexall("(?i)^iam:(add|attach|create|delete|detach|pass|put|remove|tag|untag|update)", action)) > 0
        ])
      ]
    ]))
    error_message = "Mutating IAM actions must target aws-pam-* ARNs."
  }

  assert {
    condition = alltrue(flatten([
      for policy in values(aws_iam_policy.deploy) : [
        for statement in jsondecode(policy.policy).Statement :
        alltrue([for resource in flatten([statement.Resource]) : resource != "*"])
        if anytrue([
          for action in flatten([statement.Action]) :
          startswith(lower(action), "secretsmanager:") &&
          !contains(["secretsmanager:describesecret", "secretsmanager:getresourcepolicy", "secretsmanager:getsecretvalue", "secretsmanager:listsecrets"], lower(action))
        ])
      ]
    ]))
    error_message = "Secrets Manager mutations must not target all resources."
  }

  assert {
    condition = alltrue(flatten([
      for policy in values(aws_iam_policy.deploy) : [
        for statement in jsondecode(policy.policy).Statement :
        !contains(flatten([statement.Resource]), "*") ||
        try(statement.Condition.StringEquals["aws:RequestTag/project"] == "aws-pam-access-showcase", false)
        if anytrue([
          for action in flatten([statement.Action]) :
          startswith(lower(action), "kms:") &&
          !contains(["kms:describekey", "kms:getkeypolicy", "kms:getkeyrotationstatus", "kms:listaliases", "kms:listgrants", "kms:listresourcetags"], lower(action))
        ])
      ]
    ]))
    error_message = "KMS mutations using Resource=* must require the project request tag."
  }

  assert {
    condition = alltrue([
      for action in [
        "ec2:AllocateAddress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateFlowLogs",
        "ec2:CreateInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:CreateRouteTable",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSubnet",
        "ec2:CreateVolume",
        "ec2:CreateVpc",
        "ec2:CreateVpcEndpoint",
        "ec2:RunInstances",
        ] : anytrue(flatten([
          for policy in values(aws_iam_policy.deploy) : [
            for statement in jsondecode(policy.policy).Statement :
            contains(flatten([statement.Action]), action) &&
            try(statement.Condition.StringEquals["aws:RequestTag/project"] == "aws-pam-access-showcase", false)
          ]
      ]))
    ])
    error_message = "Every EC2 create operation must have a project request-tag authorization."
  }

  assert {
    condition     = sha256(join("", sort(values(local.deploy_policy_documents)))) != sha256(join("", sort(values(local.destroy_policy_documents))))
    error_message = "Deploy and destroy policy JSON must be distinct."
  }

  assert {
    condition     = alltrue([for policy in values(aws_iam_policy.deploy) : length(policy.policy) <= 6144]) && alltrue([for policy in values(aws_iam_policy.destroy) : length(policy.policy) <= 6144])
    error_message = "Each managed policy must remain within the IAM 6,144-character limit."
  }

  assert {
    condition = !strcontains(join("", concat(
      values(local.deploy_policy_documents),
      values(local.destroy_policy_documents),
      [local.plan_policy],
    )), "resourcegroupstaggingapi:")
    error_message = "Resource Groups Tagging API permissions must use the tag service prefix."
  }

  assert {
    condition = alltrue([
      for action in flatten([
        for policy in concat(values(local.deploy_policy_documents), values(local.destroy_policy_documents)) : flatten([
          for statement in jsondecode(policy).Statement : flatten([statement.Action])
        ])
      ]) : !contains(["budgets:CreateBudget", "budgets:DeleteBudget"], action)
    ])
    error_message = "AWS Budgets create and delete operations must use budgets:ModifyBudget."
  }
}
