output "instance_id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
output "data_volume_id" { value = aws_ebs_volume.data.id }

