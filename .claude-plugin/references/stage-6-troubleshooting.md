# 階段 6：踩坑排錯 ⬜

[← 回到方法論](../SKILL.md) | [← 上一階段](stage-5-ingress-tls.md) | [下一階段 →](stage-7-gitops.md)

---

**對應文件：**
- `docs/troubleshooting/logging/2026-02-10-nlb-troubleshooting.md`
- `docs/troubleshooting/logging/troubleshooting.md`

**預計學習概念：**
- NodePort vs hostPort vs hostNetwork 的差異
- OCI Ubuntu iptables 預設規則與 K8s 的衝突
- NLB Health Check 機制與 Backend 配置
- 排錯思路：從外到內逐層排查（NLB → iptables → Pod）
- `no route to host` vs `connection refused` 的差異

**研究問題（Phase 1）：**
- [ ] `no route to host` vs `connection refused` vs `connection timed out` 各代表封包在哪一層被擋？
- [ ] OCI Ubuntu 的預設 iptables 規則為什麼會擋 K8s 流量？OCI 的安全模型（Security List + iptables）如何疊加？
- [ ] NLB (Layer 4) 的 Health Check 機制：TCP check vs HTTP check 的差異？check interval / threshold 怎麼設？
- [ ] K8s 排錯的系統性方法論：業界常見的 troubleshooting framework（例如 OSI layer-by-layer）
- [ ] 當 Pod 起不來時，`kubectl describe pod` / `kubectl logs` / `kubectl get events` 各看到什麼資訊？

**使用情境：**
- **為什麼要學排錯？** 你的 NLB troubleshooting 記錄就是最好的例子：Terraform apply 成功 ≠ 流量能通。基礎設施正常不代表應用正常，中間有 iptables、port binding、health check 等多層可能出問題。
- **不學會怎樣？** 卡在「Terraform 說成功了但 curl 不通」的黑盒狀態，只能亂猜或重建。你的 NLB 問題如果沒有系統性排查，可能反覆 taint/rebuild 卻不知道根因。
- **學了的代價？** 需要理解多層網路堆疊（L4 NLB → L3 iptables → L7 Ingress），知識門檻較高。但這恰好是 K8s 運維最核心的技能。

**情境延伸 — K8s 可觀測性 Pattern 比較：**

| 方案 | 解決什麼問題 | 優點 | 缺點 |
|------|-------------|------|------|
| **手動 kubectl + ss + iptables (你目前的方式)** | 即時排查特定問題 | 零額外資源、直接有效 | 不可重現、依賴經驗、沒有歷史紀錄 |
| **Prometheus + Grafana** | 指標監控（CPU/RAM/request count） | 視覺化 dashboard、告警機制 | 需要額外資源（RAM 敏感，你只有 24GB） |
| **Loki + Promtail** | 集中式 log 收集 | 輕量（比 ELK 省很多）、與 Grafana 整合 | 仍需額外 Pod 跑 agent |
| **kubeshark / Hubble** | 即時網路流量觀測 | 看到 Pod 間的實際 HTTP 請求 | 資源消耗大、不適合 Always Free |

> 在你的 Always Free 環境中，手動排查 + 文件記錄（你已經在做的）是最務實的方式。

**驗證指令：**
```bash
ssh oci-cp 'sudo iptables -L INPUT -n --line-numbers'      # 查看 iptables 規則
ssh oci-cp 'ss -tlnp | grep -E ":80|:443"'                 # 確認 port 監聽
```

**破壞實驗：**
- 實驗 1：在 iptables 中插入一條 REJECT 規則擋 port 80 → 觀察外部流量被拒 → 刪除該規則修復
- 實驗 2：故意用錯誤的 port 建立 NLB backend → 觀察 Health Check 失敗狀態
- ⚠️ 注意：iptables 實驗前先 `sudo iptables -L INPUT -n --line-numbers` 記錄當前規則，方便回復

**概念連結：**
- → [階段 1（架構）](stage-1-architecture.md)：排錯就是沿著流量路徑圖逐層檢查的過程
- → [階段 4（網路）](stage-4-networking.md)：iptables 規則直接影響 Pod/Service/Node 三層網路
- → [階段 5（Ingress）](stage-5-ingress-tls.md)：NLB → Ingress 這段是最常出問題的地方（你的 troubleshooting 紀錄就是證據）

**生產環境對照：**
- 學習環境：手動 `ss` + `iptables` 排查 → 生產環境：Prometheus alerts 主動通知、Grafana dashboard 即時監控
- 學習環境：排查靠 SSH 進 Node → 生產環境：集中式 log（Loki/ELK）+ 分散式 tracing（Jaeger）
- 學習環境：NLB Health Check 失敗才發現問題 → 生產環境：synthetic monitoring 模擬使用者請求，提前發現異常

**Recall Check：**
- Q: `no route to host` 和 `connection refused` 各代表什麼？封包在哪層被擋？
- Q: OCI Ubuntu 的 iptables 預設規則為什麼會擋 K8s？REJECT 在 INPUT chain 的哪個位置？
- Q: 排查「NLB 打不通」的步驟是什麼？你會從哪裡開始查？
- Q: hostPort 和 NodePort 的根本差異是什麼？

---

## 學習筆記

（Session 完成後記錄）
