# Oracle Cloud Infrastructure Always Free Resources

> Reference: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm

## Compute

| Resource | Free Quota | Limitations |
|----------|-----------|-------------|
| VM.Standard.E2.1.Micro (AMD) | 2 instances; 1/8 OCPU, 1 GB RAM, 50 Mbps | Home region only; idle 7 days may be reclaimed |
| VM.Standard.A1.Flex (Arm) | 3,000 OCPU hrs/mo + 18,000 GB hrs/mo (= 4 OCPU + 24 GB RAM) | Flexible allocation; idle 7 days may be reclaimed |
| Total instances | Up to 4 (depends on boot volume & OCPU allocation) | Min boot volume 47 GB/instance |

## Storage

| Resource | Free Quota | Limitations |
|----------|-----------|-------------|
| Block Volume | 200 GB (boot + block combined); 5 backups | Home region only |
| Object Storage | 20 GB (Standard + Infrequent + Archive combined); 50,000 API requests/mo | Objects exceeding limit deleted after trial expiry |

## Database

| Resource | Free Quota | Limitations |
|----------|-----------|-------------|
| Autonomous Database | 2 instances; 1 OCPU + 20 GB each | Cannot scale; max 20 concurrent sessions |
| NoSQL Database | 133M reads/mo + 133M writes/mo; 3 tables; 25 GB/table | - |
| MySQL HeatWave | 1 standalone DB; 50 GB data + 50 GB backup | Home region only; single node |

## Networking

| Resource | Free Quota | Limitations |
|----------|-----------|-------------|
| VCN | Up to 2 (IPv4/IPv6) | TCP port 25 blocked by default |
| Flexible Load Balancer | 1; 10 Mbps bandwidth | Tenancies created after 2020/12/15 |
| Network Load Balancer | 1; 50 listeners, 1024 backend servers | - |
| Site-to-Site VPN | Up to 50 IPSec connections | - |
| VCN Flow Logs | 10 GB/mo (shared with Logging) | - |
| Outbound Data Transfer | 10 TB/mo | - |

## Security

| Resource | Free Quota | Limitations |
|----------|-----------|-------------|
| Certificates | 5 CAs + 150 certificates | - |
| Vault | Unlimited software keys; 20 HSM key versions; 150 secrets | No Virtual Private Vault |
| Bastion | Free SSH jump access | Time-limited sessions |

## Observability & Management

| Resource | Free Quota | Limitations |
|----------|-----------|-------------|
| Monitoring | 500M ingestion + 1B retrieval data points | - |
| Notifications | 1M HTTPS + 1,000 email/mo | - |
| Email Delivery | 3,000 emails/mo | - |
| APM | 1,000 tracing events + 10 Synthetic Monitor runs/hr | - |
| Connector Hub | 2 connectors | - |
| Console Dashboards | 100/tenancy | - |
| Logging | 10 GB/mo | Shared with VCN Flow Logs |
| Resource Manager | 100 stacks, 2 concurrent jobs, 100 templates | - |

## Key Notes

- Most Always Free resources are **home region only**
- Compute instances idle for 7 days (CPU, network, memory all <20%) **may be reclaimed**
- These resources are **permanently free** and do not expire after trial period
