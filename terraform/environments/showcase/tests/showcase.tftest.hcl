mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws-pam/test"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:budget-alerts"
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:GetCallerIdentity\",\"Resource\":\"*\"}]}"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_prefix_list" {
    defaults = { id = "pl-12345678" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

run "secure_topology" {
  command = apply

  variables {
    deployment_enabled       = true
    deployment_id            = "test123"
    operator_cidr            = "198.51.100.10/32"
    authorization_expiration = "2099-01-01T00:00:00Z"
    expiration               = "2099-01-01"
    deployment_role_arn      = "arn:aws:iam::123456789012:role/aws-pam-test-github-deploy"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.sensitive_ssh.referenced_security_group_id == aws_security_group.jumpserver.id
    error_message = "Sensitive SSH must reference only the JumpServer security group."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.openvpn_udp.cidr_ipv4 == "198.51.100.10/32"
    error_message = "OpenVPN ingress must retain the exact operator CIDR."
  }

  assert {
    condition     = module.openvpn.private_ip == "10.42.0.10" && module.jumpserver.private_ip == "10.42.10.10"
    error_message = "The narrow VPN route depends on stable private addresses."
  }
}
