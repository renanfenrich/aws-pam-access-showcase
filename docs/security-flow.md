# Security flow

1. The operator's explicit public `/32` can reach only OpenVPN UDP 1194.
2. The client certificate is validated by the private OpenVPN CA and can be revoked through a CRL.
3. The VPN server pushes only the JumpServer private `/32`; it does not push the VPC or isolated subnet.
4. The client reaches JumpServer on HTTPS 443 or proxy 2222. Security groups and the host firewall allow only the VPN client CIDR.
5. JumpServer authenticates `portfolio-operator`, forces MFA enrollment, and evaluates the exact asset authorization.
6. The permission grants only SSH `connect` to one asset through one managed `jms-operator` account. Upload, download, delete, clipboard, and sharing actions are absent.
7. JumpServer brokers the target key; the user never retrieves it.
8. The target accepts TCP 22 only from the JumpServer security group. Its account is non-root, password-locked, and has no sudo policy.
9. JumpServer records the session and command history. A scoped command filter rejects the demonstration commands before execution.

Network possession and privileged authorization are separate trust decisions. A stolen VPN profile provides a route to JumpServer, not a route or credential to the target.
