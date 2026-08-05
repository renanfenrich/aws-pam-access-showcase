resource "aws_kms_key" "data" {
  description             = "JumpServer data volume encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name}-jumpserver-data"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
    kms_key_id  = aws_kms_key.data.arn
  }

  tags = {
    Name = "${var.name}-jumpserver"
    Role = "jumpserver"
  }

  lifecycle {
    precondition {
      condition     = can(regex("^(t3|t3a|m[5-9][a-z]*)\\.xlarge$", var.instance_type))
      error_message = "JumpServer must use at least a 4-vCPU, 8-GiB instance class."
    }
  }
}

resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  encrypted         = true
  kms_key_id        = aws_kms_key.data.arn
  size              = 80
  type              = "gp3"

  tags = { Name = "${var.name}-jumpserver-data" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id
}

