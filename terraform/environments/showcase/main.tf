data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

locals {
  name = "aws-pam-${var.deployment_id}"
  default_tags = {
    project     = "aws-pam-access-showcase"
    environment = "showcase"
    owner       = var.owner
    managed-by  = "terraform"
    expiration  = var.expiration == "" ? "not-set" : var.expiration
    deployment  = var.deployment_id
  }
  vpc_cidr              = "10.42.0.0/16"
  public_subnet_cidr    = "10.42.0.0/24"
  access_subnet_cidr    = "10.42.10.0/24"
  isolated_subnet_cidr  = "10.42.20.0/24"
  openvpn_private_ip    = "10.42.0.10"
  jumpserver_private_ip = "10.42.10.10"
  sensitive_private_ip  = "10.42.20.10"
  vpc_dns_resolver      = cidrhost(local.vpc_cidr, 2)
}

resource "terraform_data" "deployment_gate" {
  input = var.deployment_id

  lifecycle {
    precondition {
      condition     = var.deployment_enabled
      error_message = "Refusing to plan or provision: set deployment_enabled=true explicitly."
    }
    precondition {
      condition     = var.operator_cidr != "" && var.operator_cidr != "0.0.0.0/0"
      error_message = "A non-public, explicit operator_cidr is required."
    }
    precondition {
      condition     = var.authorization_expiration != "" && timecmp(var.authorization_expiration, timestamp()) > 0
      error_message = "authorization_expiration must be a future RFC3339 timestamp."
    }
    precondition {
      condition     = var.expiration != ""
      error_message = "An explicit expiration tag is required."
    }
    precondition {
      condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+", var.deployment_role_arn))
      error_message = "deployment_role_arn must be the bootstrap-created GitHub deployment role ARN."
    }
    precondition {
      condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/aws-pam-.+", var.permissions_boundary_arn))
      error_message = "permissions_boundary_arn must be the bootstrap-created workload boundary ARN."
    }
  }
}

module "network" {
  source = "../../modules/network"

  name                 = local.name
  vpc_cidr             = local.vpc_cidr
  availability_zone    = data.aws_availability_zones.available.names[0]
  public_subnet_cidr   = local.public_subnet_cidr
  access_subnet_cidr   = local.access_subnet_cidr
  isolated_subnet_cidr = local.isolated_subnet_cidr

  depends_on = [terraform_data.deployment_gate]
}

module "ssm" {
  source = "../../modules/ssm"

  name                     = local.name
  deployment_role_arn      = var.deployment_role_arn
  permissions_boundary_arn = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  for_each = module.ssm.instance_role_names

  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

module "secrets" {
  source = "../../modules/secrets"

  name                 = local.name
  deployment_role_arn  = var.deployment_role_arn
  openvpn_role_name    = module.ssm.instance_role_names["openvpn"]
  openvpn_role_arn     = module.ssm.instance_role_arns["openvpn"]
  jumpserver_role_name = module.ssm.instance_role_names["jumpserver"]
  jumpserver_role_arn  = module.ssm.instance_role_arns["jumpserver"]
}

module "openvpn" {
  source = "../../modules/openvpn"

  name                  = local.name
  ami_id                = data.aws_ssm_parameter.al2023_ami.value
  subnet_id             = module.network.public_subnet_id
  security_group_id     = aws_security_group.openvpn.id
  instance_profile_name = module.ssm.instance_profile_names["openvpn"]
  private_ip            = local.openvpn_private_ip
  instance_type         = var.openvpn_instance_type
}

module "jumpserver" {
  source = "../../modules/jumpserver"

  name                  = local.name
  ami_id                = data.aws_ssm_parameter.al2023_ami.value
  availability_zone     = data.aws_availability_zones.available.names[0]
  subnet_id             = module.network.access_subnet_id
  security_group_id     = aws_security_group.jumpserver.id
  instance_profile_name = module.ssm.instance_profile_names["jumpserver"]
  private_ip            = local.jumpserver_private_ip
  instance_type         = var.jumpserver_instance_type
}

module "sensitive_resource" {
  source = "../../modules/sensitive-resource"

  name                  = local.name
  ami_id                = data.aws_ssm_parameter.al2023_ami.value
  subnet_id             = module.network.isolated_subnet_id
  security_group_id     = aws_security_group.sensitive.id
  instance_profile_name = module.ssm.instance_profile_names["sensitive-resource"]
  private_ip            = local.sensitive_private_ip
  instance_type         = var.sensitive_instance_type
}

resource "aws_route" "vpn_return" {
  route_table_id         = module.network.access_route_table_id
  destination_cidr_block = var.vpn_client_cidr
  network_interface_id   = module.openvpn.network_interface_id
}

module "observability" {
  source = "../../modules/observability"

  name                = local.name
  vpc_id              = module.network.vpc_id
  monthly_budget_usd  = var.monthly_budget_usd
  budget_email        = var.budget_email
  flow_log_bucket_arn = module.ssm.transfer_bucket_arn
}

check "sensitive_resource_has_no_internet_route" {
  assert {
    condition     = module.network.isolated_route_table_id != module.network.public_route_table_id && module.network.isolated_route_table_id != module.network.access_route_table_id
    error_message = "Sensitive resources must use their dedicated no-default-route table."
  }
}

check "vpn_advertises_only_jumpserver" {
  assert {
    condition     = cidrhost("${local.jumpserver_private_ip}/32", 0) != local.sensitive_private_ip
    error_message = "The VPN route must be a JumpServer-only /32, never the sensitive subnet."
  }
}
