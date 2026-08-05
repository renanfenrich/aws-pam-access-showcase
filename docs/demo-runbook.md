# Manual demonstration runbook

Complete this only after the protected deployment passes. Use an authenticated local AWS session authorized to read only the VPN profile and public TLS CA certificate.

1. Retrieve the current OpenVPN profile without printing it to terminal history:

   ```bash
   umask 077
   aws-vault exec <profile> -- aws secretsmanager get-secret-value \
     --secret-id <deployment-prefix>/openvpn-demo-client-profile \
     --query SecretString --output text > demo-client.ovpn
   ```

2. Retrieve the JumpServer public CA certificate from `<deployment-prefix>/jumpserver-tls-ca-certificate`, save it as `jumpserver-ca.crt`, and install it in the workstation's trusted certificate store. This secret contains only the public CA certificate.
3. Connect with OpenVPN Community Edition using `demo-client.ovpn`.
4. Inspect the client route table. Record that it contains the JumpServer `/32`, not `10.42.0.0/16` or `10.42.20.0/24`.
5. Open `https://10.42.10.10/` and confirm the private CA is trusted.
6. Attempt direct SSH to `10.42.20.10`; it must fail. Record the source, destination, TCP 22, and expected denial without exposing addresses in public screenshots.
7. Sign in as `portfolio-operator` using the initial password retrieved through a tightly scoped operator process.
8. Enroll MFA when JumpServer forces setup, then reauthenticate.
9. Confirm that exactly one authorized asset, `sensitive-resource`, is visible.
10. Open its browser terminal with the managed `jms-operator` account.
11. Run:

    ```bash
    hostname
    id
    cat /opt/private-resource/status.txt
    ```

12. Attempt `sudo -i`. JumpServer must reject it; do not attempt a destructive bypass.
13. Log out and open the JumpServer audit interface.
14. Locate the completed session, confirm its command history contains the allowed commands and denied `sudo -i`, and confirm a session recording exists.
15. Run the protected revoke operation (`make revoke-vpn-client` only inside the authorized workflow) and verify a new connection with the old profile fails.
16. Run the protected destroy workflow with `DESTROY`.

## Screenshot checklist

- Narrow client route, single authorized asset, restricted `id`, status file, denied-command banner, audit command entry, session-history row, recording-exists indicator, and successful destroy summary.
- Redact credentials, private/public IP addresses not needed for the claim, account IDs, tokens, browser session identifiers, QR/MFA seeds, and timestamps that expose internal operational detail.
- Never commit raw recordings or screenshots containing secrets.
