output "deployment" {
  description = "Non-secret deployment inventory consumed by Ansible and verification."
  value = {
    deployment_id               = var.deployment_id
    region                      = var.aws_region
    vpc_id                      = module.network.vpc_id
    vpn_client_cidr             = var.vpn_client_cidr
    operator_cidr               = var.operator_cidr
    authorization_expiration    = var.authorization_expiration
    openvpn_instance_id         = module.openvpn.instance_id
    openvpn_private_ip          = module.openvpn.private_ip
    openvpn_public_ip           = module.openvpn.public_ip
    jumpserver_instance_id      = module.jumpserver.instance_id
    jumpserver_private_ip       = module.jumpserver.private_ip
    jumpserver_data_volume_id   = module.jumpserver.data_volume_id
    sensitive_instance_id       = module.sensitive_resource.instance_id
    sensitive_private_ip        = module.sensitive_resource.private_ip
    ansible_transfer_bucket     = module.ssm.transfer_bucket
    ansible_transfer_kms_key_id = module.ssm.transfer_kms_key_arn
    isolated_route_table_id     = module.network.isolated_route_table_id
    security_group_ids = {
      openvpn            = aws_security_group.openvpn.id
      jumpserver         = aws_security_group.jumpserver.id
      sensitive_resource = aws_security_group.sensitive.id
    }
    secret_names = module.secrets.secret_names
    log_groups   = module.observability.log_group_names
  }
}

output "secret_arns" {
  description = "Secret container ARNs only; never secret values."
  value       = module.secrets.secret_arns
}
