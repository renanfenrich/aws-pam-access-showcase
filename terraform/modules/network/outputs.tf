output "vpc_id" { value = aws_vpc.this.id }
output "vpc_cidr" { value = aws_vpc.this.cidr_block }
output "public_subnet_id" { value = aws_subnet.public.id }
output "access_subnet_id" { value = aws_subnet.access.id }
output "isolated_subnet_id" { value = aws_subnet.isolated.id }
output "public_route_table_id" { value = aws_route_table.public.id }
output "access_route_table_id" { value = aws_route_table.access.id }
output "isolated_route_table_id" { value = aws_route_table.isolated.id }
output "endpoint_security_group_id" { value = aws_security_group.endpoints.id }
output "endpoint_ids" { value = merge({ for name, endpoint in aws_vpc_endpoint.interface : name => endpoint.id }, { s3 = aws_vpc_endpoint.s3.id }) }

