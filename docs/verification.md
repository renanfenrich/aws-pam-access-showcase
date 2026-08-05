# Verification

Static CI proves syntax, policy intent, immutable references, and repository structure without AWS credentials. It does not prove deployed behavior.

The protected deployment verifies through AWS APIs and Systems Manager:

- public-IP absence, isolated routing, exact security-group sources, IMDSv2, EBS encryption, no EC2 key pairs, and SSM online state;
- failed OpenVPN-host → target TCP 22 and successful JumpServer-host → target TCP 22, with source/destination/port recorded;
- private JumpServer health and the expected user, one asset, managed account, SSH-only expiring authorization, transfer denial, and command filter;
- zero-change second Ansible run and zero-change second Terraform plan.

Machine-readable files are summarized in `evidence/summary.md`. A check reports `pass` only from an explicit predicate. Timeouts are never treated as standalone proof; negative network evidence includes the expected source, destination, port, and observed result.

The denied command, command audit, session history, and recording require the human steps in `docs/demo-runbook.md` because automation must not fabricate user-session evidence.
