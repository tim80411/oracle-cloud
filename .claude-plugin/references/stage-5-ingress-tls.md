# 階段 5：Ingress & TLS ⬜

[← 回到方法論](../SKILL.md) | [← 上一階段](stage-4-networking.md) | [下一階段 →](stage-6-troubleshooting.md)

---

**對應文件：**
- `docs/learning/logging/layer2-installation-report.md` (Ingress 部分)
- `docs/troubleshooting/logging/2026-02-10-nlb-troubleshooting.md`

**預計學習概念：**
- Ingress 資源：L7 路由規則（host-based / path-based）
- ingress-nginx：反向代理的角色、hostNetwork 為什麼必要
- cert-manager：ACME 協議、HTTP-01 challenge 流程
- Let's Encrypt：自動 TLS 憑證的生命週期
- NLB (Layer 4) vs Ingress (Layer 7) 的分工

**研究問題（Phase 1）：**
- [ ] Ingress 資源和 Ingress Controller 的關係？為什麼光有 Ingress YAML 不夠？
- [ ] hostNetwork vs hostPort vs NodePort — 三者的網路原理差異？你的 NLB troubleshooting 踩的坑屬於哪種？
- [ ] ACME 協議的 HTTP-01 vs DNS-01 challenge 分別怎麼運作？各適合什麼場景？
- [ ] cert-manager 從申請到掛載 TLS 憑證的完整流程（Certificate → CertificateRequest → Order → Challenge）
- [ ] Gateway API 跟 Ingress 的根本設計差異是什麼？為什麼 K8s 社群要重新設計？

**使用情境：**
- **為什麼需要 Ingress？** 你有多個服務（ArgoCD、echo-server、apple-crawler），但只有 1 個 NLB Public IP。Ingress 讓你用不同 hostname/path 路由到不同後端，就像一個共享的反向代理。
- **不用會怎樣？** 每個服務用 NodePort 暴露，使用者要記住 `IP:30001`、`IP:30002` 這種高位 port。沒有 TLS、沒有域名路由。或者每個服務配一個 LoadBalancer，但 OCI Always Free 只給 1 個 NLB。
- **用了的代價？** ingress-nginx 本身佔用資源（約 100-200MB RAM），需要處理 hostNetwork/hostPort 設定（你在 NLB troubleshooting 中踩過這個坑）。cert-manager 又多 3 個 Pod。

**情境延伸 — Ingress Controller 比較：**

| 方案 | 適合場景 | 優點 | 缺點 |
|------|---------|------|------|
| **ingress-nginx (你的選擇)** | 通用場景、社群最大 | 功能最完整、文件最多、基於 nginx | 設定靠 annotation（容易亂）、效能非頂尖 |
| **Traefik** | 動態環境、自動服務發現 | 自帶 dashboard、原生支援 Let's Encrypt | 進階功能需付費版 (Traefik Enterprise) |
| **Gateway API (K8s 原生)** | 新專案、追求標準化 | K8s 官方標準、取代 Ingress 的下一代 API | 較新（部分 controller 支援不完整） |
| **Nginx (手動部署)** | 極簡、完全控制 | 最熟悉、配置自由度最高 | 完全手動管理、不整合 K8s 自動發現 |

> ingress-nginx 是目前最安全的選擇。但 Gateway API 是 K8s 的未來方向，值得關注。

**驗證指令：**
```bash
ssh oci-cp 'kubectl get ingress -A'                         # 查看 Ingress 規則
ssh oci-cp 'kubectl get certificate -A'                     # 查看 TLS 憑證狀態
ssh oci-cp 'kubectl describe ingress -n argocd'             # 查看 ArgoCD Ingress 細節
```

**破壞實驗：**
- 實驗 1：建一個 Ingress 指向不存在的 Service → 觀察 502 Bad Gateway 回應
- 實驗 2：修改 echo-server 的 Ingress host 為錯誤域名 → 觀察 404 回應 → 改回正確域名修復
- 實驗 3：`ssh oci-cp 'kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=0'` → 所有外部流量中斷 → scale 回 1 修復
- ⚠️ 注意：實驗 3 會讓 ArgoCD Web UI 也斷線，確保你有 SSH 存取可以修復

**概念連結：**
- → [階段 4（網路）](stage-4-networking.md)：Ingress 是 L7 層，底下還有 Service（L4）和 Pod Network
- → [階段 6（排錯）](stage-6-troubleshooting.md)：NLB troubleshooting 的核心就是 Ingress 層的 hostPort 問題
- → [階段 7（GitOps）](stage-7-gitops.md)：ArgoCD 的 Ingress 設定是 Layer 3 GitOps 的入口

**生產環境對照：**
- 學習環境：單個 ingress-nginx replica → 生產環境：多 replica + PodAntiAffinity（分散到不同 Node）
- 學習環境：Let's Encrypt HTTP-01 → 生產環境：大型組織可能用 DNS-01（支援 wildcard cert）或自簽 CA
- 學習環境：hostPort 綁定 → 生產環境：雲端 LoadBalancer Service 類型，由 cloud provider 自動分配 LB

**Recall Check：**
- Q: Ingress 資源和 Ingress Controller 的關係是什麼？
- Q: cert-manager 申請憑證的完整流程？（Certificate → Order → Challenge）
- Q: 你的 NLB 為什麼需要 hostPort？如果用 NodePort 會有什麼問題？
- Q: HTTP-01 和 DNS-01 challenge 各適合什麼場景？

---

## 學習筆記

（Session 完成後記錄）
