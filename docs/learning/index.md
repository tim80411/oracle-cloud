# Learning Path

深入理解本專案用到的技術概念。適合想知道「為什麼這樣做」和「背後原理是什麼」的讀者。

> **學習方法論已整合至 skill**: 完整的 5-phase 學習流程請參考 `.claude-plugin/skills/k8s-learning.md`。
> 說「繼續階段 N」即可啟動自動研究 + 學習流程。

## Recommended Reading Order

### 1. K8s 安裝與網路基礎

從 Layer 2 安裝報告開始，涵蓋：
- kubeadm 叢集初始化流程與參數解析
- OCI Ubuntu iptables 預設規則與修復（`no route to host` vs `connection refused`）
- Kubernetes 三層網路模型：Node / Pod (Flannel CNI) / Service (kube-proxy)
- ingress-nginx、cert-manager、ACME 協議

**[logging/layer2-installation-report.md](logging/layer2-installation-report.md)**

### 2. GitOps 實戰踩坑

Layer 3 原始操作紀錄，保留真實錯誤與修復過程：
- SSH heredoc 在遠端執行的陷阱（nested SSH 解析問題）
- ARM 架構 image 相容性（`exec format error`）
- Cloudflare Proxy vs DNS-only 對 Let's Encrypt HTTP-01 的影響
- ingress-nginx admission webhook 與 cert-manager 的衝突
- path-based routing 的 rewrite-target 設定

**[logging/layer3-setup-raw-log.md](logging/layer3-setup-raw-log.md)**

## Key Concepts Map

```
Terraform (IaC)
    └─ cloud-init (OS bootstrap)
        └─ kubeadm (K8s cluster)
            ├─ Flannel (Pod networking, VXLAN overlay)
            ├─ kube-proxy (Service → Pod routing, iptables NAT)
            ├─ ingress-nginx (L7 reverse proxy, hostNetwork)
            ├─ cert-manager (TLS, ACME, Let's Encrypt)
            └─ ArgoCD (GitOps, App-of-Apps pattern)
```

## 結構化學習階段

階段檔案位於 `.claude-plugin/references/`，詳見 [學習計畫快速索引](k8s-learning-plan.md)。
