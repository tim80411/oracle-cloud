# Troubleshooting Quick Reference

症狀 → 解法速查。詳細診斷步驟見 logging/ 目錄。

## TODO(human): Symptom-Solution Quick Lookup Table

<!--
Design this table as a fast triage tool.
Each row: symptom the operator sees → likely cause → fix action or link.
Extract from the two logging files below.
-->

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| | | |

## Diagnostic Tools

```bash
# NLB automated check
./scripts/check-nlb.sh          # check only
./scripts/check-nlb.sh --fix    # check + remediation commands

# K8s cluster health
ssh oci-cp 'kubectl get nodes && kubectl get pods -A'

# iptables rules (check for REJECT blocking traffic)
ssh oci-cp 'sudo iptables -L INPUT -n --line-numbers'

# Ingress controller status
ssh oci-cp 'kubectl get pods -n ingress-nginx && ss -tlnp | grep -E ":80|:443"'

# cert-manager / TLS status
ssh oci-cp 'kubectl get certificate -A && kubectl get challenge -A'
```

## Detailed Guides

- **[logging/troubleshooting.md](logging/troubleshooting.md)** — 通用診斷指南（OCI 帳號、NLB、iptables、Ingress）
- **[logging/2026-02-10-nlb-troubleshooting.md](logging/2026-02-10-nlb-troubleshooting.md)** — NLB 連線問題根因分析（HostPort、iptables、Reserved IP 綁定失效）
