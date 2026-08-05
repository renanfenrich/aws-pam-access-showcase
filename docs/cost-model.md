# Cost model

Approximate `us-east-1` defaults as of August 2026:

| Component | Approximate cost |
| --- | ---: |
| `t3.xlarge` JumpServer | USD 0.1670/hour |
| Two `t3.micro` instances | USD 0.0208/hour |
| One NAT Gateway | about USD 0.045/hour plus data |
| Four interface endpoints | about USD 0.040/hour plus data |
| One public IPv4 address | USD 0.005/hour |
| 122 GiB gp3, secrets, and four main-stack KMS keys | roughly USD 18/month plus API use |

The active estimate is about **USD 0.30/hour** and **USD 220/month** at 730 hours, before NAT processing, endpoint data, Internet transfer, CloudWatch ingestion, taxes, or T3 unlimited CPU credits. The permanent bootstrap key and small state storage add roughly another USD 1/month plus requests.

AWS pricing changes and varies by region. Recalculate with the AWS Pricing Calculator before deployment. The budget default should be set above the expected short showcase window, alerts are not spend caps, and immediate protected destroy is the primary cost control.
