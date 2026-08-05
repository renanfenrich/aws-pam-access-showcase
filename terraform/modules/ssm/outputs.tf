output "instance_profile_names" { value = { for name, profile in aws_iam_instance_profile.instance : name => profile.name } }
output "instance_role_names" { value = { for name, role in aws_iam_role.instance : name => role.name } }
output "instance_role_arns" { value = { for name, role in aws_iam_role.instance : name => role.arn } }
output "instance_role_boundaries" { value = { for name, role in aws_iam_role.instance : name => role.permissions_boundary } }
output "transfer_bucket" { value = aws_s3_bucket.transfer.id }
output "transfer_bucket_arn" { value = aws_s3_bucket.transfer.arn }
output "transfer_kms_key_arn" { value = aws_kms_key.transfer.arn }
