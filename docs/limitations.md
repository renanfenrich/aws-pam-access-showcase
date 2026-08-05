# Limitations

- One Availability Zone, one OpenVPN host, one JumpServer host, and local PostgreSQL/Redis: no high availability.
- A NAT Gateway and interface endpoints dominate short-run networking cost but keep the security boundaries explicit.
- The private CA has a short showcase lifetime and manual workstation trust installation.
- One locally authenticated demonstration user with manual MFA enrollment; no enterprise IdP or lifecycle integration.
- Recordings remain on the encrypted instance volume and are not immutable or independently durable.
- The host firewall complements security groups but is not a substitute for fleet-wide network policy governance.
- GitHub environment reviewers, self-approval prevention, and branch policies require repository-administrator configuration outside source control.
- Live JumpServer UI/session/audit proof is manual. Static CI cannot establish that a deployment occurred.
- AWS least privilege is constrained by services whose create/describe APIs require wildcard resources; bootstrap policies should be tightened further with organization controls and permission boundaries in production.

Production requires external HA databases/caches, durable and tamper-resistant recording storage, backups with restore tests, stronger identity, managed PKI, centralized alerting, formal ownership, incident response, capacity testing, patch governance, and disaster recovery.
