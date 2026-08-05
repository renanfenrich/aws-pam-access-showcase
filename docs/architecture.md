# Architecture

The VPC is `10.42.0.0/16` in one configurable AWS region and Availability Zone.

| Subnet | CIDR | Route | Workload |
| --- | --- | --- | --- |
| Public | `10.42.0.0/24` | Internet Gateway | OpenVPN EC2 and Elastic IP; no SSH ingress |
| Private access | `10.42.10.0/24` | NAT for installation/updates | JumpServer at stable private address `10.42.10.10` |
| Isolated | `10.42.20.0/24` | No default route | Amazon Linux 2023 target at `10.42.20.10` |

Interface endpoints for SSM, SSM Messages, EC2 Messages, and Secrets Manager are placed in the private access subnet with private DNS. A gateway endpoint attaches S3 to all route tables. The isolated instance egress permits private endpoint TLS, regional S3 prefix-list TLS, and VPC DNS only.

The private access route table sends only the VPN client CIDR back to the OpenVPN ENI. No VPN route exists in the isolated route table. OpenVPN source/destination checking is disabled solely because it forwards VPN packets.

JumpServer `v4.10.18` is installed from a SHA-256 verified release archive. The showcase enables only core, celery, web, and Koko plus local PostgreSQL and Redis. Relevant container images are pinned to multi-architecture manifest digests in `ansible/roles/jumpserver/defaults/main.yml`. Its encrypted 80 GiB data volume persists `/data/jumpserver`.

This topology deliberately favors a clear control proof over availability.
