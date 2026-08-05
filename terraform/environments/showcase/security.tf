resource "aws_security_group" "openvpn" {
  name        = "${local.name}-openvpn"
  description = "OpenVPN only; no inbound administrative SSH"
  vpc_id      = module.network.vpc_id
  tags        = { Name = "${local.name}-openvpn" }
}

resource "aws_vpc_security_group_ingress_rule" "openvpn_udp" {
  security_group_id = aws_security_group.openvpn.id
  description       = "OpenVPN from the explicit operator address"
  cidr_ipv4         = var.operator_cidr
  from_port         = 1194
  to_port           = 1194
  ip_protocol       = "udp"
}

resource "aws_security_group" "jumpserver" {
  name        = "${local.name}-jumpserver"
  description = "JumpServer UI and SSH proxy from VPN clients only"
  vpc_id      = module.network.vpc_id
  tags        = { Name = "${local.name}-jumpserver" }
}

resource "aws_vpc_security_group_ingress_rule" "jumpserver_vpn" {
  for_each = { https = 443, ssh_proxy = 2222 }

  security_group_id = aws_security_group.jumpserver.id
  description       = "${each.key} from authenticated VPN clients"
  cidr_ipv4         = var.vpn_client_cidr
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
}

resource "aws_security_group" "sensitive" {
  name        = "${local.name}-sensitive-resource"
  description = "SSH exclusively from the JumpServer security group"
  vpc_id      = module.network.vpc_id
  tags        = { Name = "${local.name}-sensitive-resource" }
}

resource "aws_vpc_security_group_ingress_rule" "sensitive_ssh" {
  security_group_id            = aws_security_group.sensitive.id
  description                  = "SSH only from JumpServer"
  referenced_security_group_id = aws_security_group.jumpserver.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "host_https" {
  for_each = {
    openvpn    = aws_security_group.openvpn.id
    jumpserver = aws_security_group.jumpserver.id
  }

  security_group_id = each.value
  description       = "HTTPS updates and AWS APIs"
  # trivy:ignore:AVD-AWS-0104 -- HTTPS-only bootstrap egress is required for pinned OS and OCI downloads through NAT.
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  for_each = {
    openvpn    = aws_security_group.openvpn.id
    jumpserver = aws_security_group.jumpserver.id
    sensitive  = aws_security_group.sensitive.id
  }

  security_group_id = each.value
  description       = "DNS to the VPC resolver"
  cidr_ipv4         = "${local.vpc_dns_resolver}/32"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  for_each = {
    openvpn    = aws_security_group.openvpn.id
    jumpserver = aws_security_group.jumpserver.id
    sensitive  = aws_security_group.sensitive.id
  }

  security_group_id = each.value
  description       = "TCP DNS fallback to the VPC resolver"
  cidr_ipv4         = "${local.vpc_dns_resolver}/32"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "jumpserver_to_sensitive" {
  security_group_id            = aws_security_group.jumpserver.id
  description                  = "SSH proxy to the single private resource"
  referenced_security_group_id = aws_security_group.sensitive.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "openvpn_to_jumpserver" {
  for_each = { https = 443, ssh_proxy = 2222 }

  security_group_id            = aws_security_group.openvpn.id
  description                  = "Forward VPN clients only to JumpServer ${each.key}"
  referenced_security_group_id = aws_security_group.jumpserver.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "sensitive_to_endpoints" {
  security_group_id            = aws_security_group.sensitive.id
  description                  = "HTTPS only to private interface endpoints"
  referenced_security_group_id = module.network.endpoint_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "sensitive_to_s3" {
  security_group_id = aws_security_group.sensitive.id
  description       = "HTTPS to the regional S3 gateway endpoint"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
