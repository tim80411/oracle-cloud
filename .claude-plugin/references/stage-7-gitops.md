# 階段 7：GitOps (ArgoCD) ⬜

[← 回到方法論](../SKILL.md) | [← 上一階段](stage-6-troubleshooting.md)

---

**對應文件：**
- `docs/learning/logging/layer3-setup-raw-log.md`（踩坑版）
- `docs/guides/logging/layer3-setup-log.md`（整理版）

**預計學習概念：**
- GitOps 原則：Git 是 single source of truth
- ArgoCD App-of-Apps pattern：一個根 Application 管理所有子 Application
- SSH Deploy Key：K8s Secret + GitHub 的認證機制
- Sync Policy：auto-sync vs manual-sync
- 踩坑：ARM image 相容性、SSH heredoc 問題、Cloudflare Proxy vs DNS-only

**研究問題（Phase 1）：**
- [ ] GitOps 的核心原則有哪些？Push-based vs Pull-based 部署的安全性差異？
- [ ] ArgoCD 的 App-of-Apps pattern 跟 ApplicationSet 的差別？各適合什麼規模？
- [ ] ArgoCD sync policy 的選項：auto-sync、self-heal、prune 各做什麼？風險是什麼？
- [ ] K8s Secret 存放 SSH key 的安全考量？為什麼你用了 Sealed Secrets？替代方案（SOPS、External Secrets）比較
- [ ] 多環境（dev/staging/prod）的 GitOps 管理策略：單 repo vs 多 repo、branch-based vs folder-based

**使用情境：**
- **為什麼用 GitOps？** 傳統部署是 `kubectl apply` 或 CI pipeline `ssh` 進集群推送。GitOps 反轉這個方向：集群主動從 Git 拉取期望狀態。這意味著 Git 歷史 = 部署歷史，rollback = git revert。
- **不用會怎樣？** 用 `kubectl apply` 也能部署，但你會面對「集群上跑的東西跟 Git 裡的不一致」（drift）。有人手動改了 replica 數、有人直接 `kubectl edit`，慢慢就沒人知道真正的狀態是什麼。
- **用了的代價？** ArgoCD 本身 7 個 Pod（你的集群裡最大的組件群），吃約 300-500MB RAM。學習 Application CRD、sync policy 等概念。但換來的是「push to git = auto deploy」的工作流。

**情境延伸 — 部署策略比較：**

| 方案 | 適合場景 | 優點 | 缺點 |
|------|---------|------|------|
| **ArgoCD (你的選擇)** | 需要 Web UI、多叢集管理 | 視覺化 dashboard、App-of-Apps、SSO 整合 | 資源佔用高（7 個 Pod）、CRD 多 |
| **FluxCD** | 輕量 GitOps、不需 UI | 更輕量、K8s 原生 CRD、CNCF 畢業 | 無內建 UI（需另裝 Weave GitOps） |
| **CI/CD Pipeline (GitHub Actions → kubectl)** | 簡單專案、push-based 部署 | 設定簡單、不需額外集群組件 | Push-based（CI 需要集群存取權）、無 drift 偵測 |
| **Helm + helmfile** | 需要模板化的複雜應用 | 參數化部署、版本管理 | 不是 GitOps（仍需手動 apply 或搭配 CI） |

> 你的 Design Decision #4 提到選 ArgoCD 而非 Flux 是因為 Web UI。在資源受限環境中 Flux 其實更省，但 ArgoCD 的視覺化對學習和 debug 很有幫助。

**驗證指令：**
```bash
ssh oci-cp 'kubectl get applications -n argocd'             # 查看 ArgoCD Applications
ssh oci-cp 'kubectl get applications -n argocd -o yaml | grep -A3 syncPolicy'  # 查看 sync 設定
```

**破壞實驗：**
- 實驗 1：直接 `kubectl edit` 修改 echo-server 的 replica 數 → 觀察 ArgoCD 偵測到 drift（OutOfSync）→ 看 auto-sync 是否自動修回
- 實驗 2：在 k8s-apps repo 中故意 push 一個語法錯誤的 YAML → 觀察 ArgoCD sync 失敗的錯誤訊息
- 實驗 3：刪除 ArgoCD 的 repo Secret → 觀察 sync 失敗（SSH authentication error）→ 重建 Secret 修復

**概念連結：**
- → [階段 1（架構）](stage-1-architecture.md)：GitOps 是 Layer 3 的核心，讓應用交付完全自動化
- → [階段 3（kubeadm）](stage-3-kubeadm.md)：ArgoCD 本身也是跑在 K8s 上的 Pod，依賴 kubeadm 建立的叢集
- → [階段 5（Ingress）](stage-5-ingress-tls.md)：ArgoCD Web UI 的對外存取依賴 Ingress + TLS 設定

**生產環境對照：**
- 學習環境：單一 repo、單一環境 → 生產環境：multi-env（dev/staging/prod），可能用 ApplicationSet 自動產生
- 學習環境：所有人有叢集 admin 權限 → 生產環境：RBAC 限制誰能 sync 哪些 Application
- 學習環境：Sealed Secrets → 生產環境：可能用 External Secrets Operator（對接 AWS Secrets Manager / Vault）
- 學習環境：手動建 SSH deploy key → 生產環境：用 OIDC 或 GitHub App 認證

**Recall Check：**
- Q: GitOps 的 Pull-based 部署跟傳統 CI/CD Push-based 有什麼安全性差異？
- Q: ArgoCD 的 auto-sync + self-heal 各做什麼？開啟 self-heal 的風險是什麼？
- Q: App-of-Apps pattern 的好處是什麼？你的根 Application 指向什麼？
- Q: 為什麼你用 Sealed Secrets 而不是直接把 Secret 放進 Git？

---

## 學習筆記

（Session 完成後記錄）
