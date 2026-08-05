resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = false
  source_dest_check           = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 12
  }

  tags = {
    Name = "${var.name}-openvpn"
    Role = "openvpn"
  }

  lifecycle {
    # The separately managed EIP makes EC2 report this flag as true after association.
    ignore_changes = [associate_public_ip_address]

    precondition {
      condition     = var.private_ip != ""
      error_message = "OpenVPN requires a stable private IP for the return route."
    }
  }
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = { Name = "${var.name}-openvpn" }
}
