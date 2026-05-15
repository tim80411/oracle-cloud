# 階段 3：叢集建立 (kubeadm) ⬜

[← 回到方法論](../SKILL.md) | [← 上一階段](stage-2-node-setup.md) | [下一階段 →](stage-4-networking.md)

---

**對應文件：**
- `docs/learning/logging/layer2-installation-report.md` (第一部分)

**預計學習概念：**
- kubeadm init：初始化 Control Plane 的完整流程
- kubeadm join：Worker 節點加入的認證機制（Bootstrap Token + CA cert hash）
- API Server 的角色：所有操作的唯一入口
- etcd：叢集狀態的 single source of truth
- Taint & Toleration：為什麼 CP 預設不排程、如何移除

**研究問題（Phase 1）：**
- [ ] `kubeadm init` 背後實際做了哪些事？（憑證、static pod manifest、etcd…）
- [ ] Bootstrap Token 的安全模型是什麼？為什麼有 24 小時過期機制？
- [ ] etcd 是什麼？為什麼 K8s 選擇 etcd 而不是其他 DB？單節點 etcd 的風險是什麼？
- [ ] Taint & Toleration 機制的設計原理？除了 CP 不排程，還有哪些常見用途？
- [ ] kubeadm 升級 K8s 版本的流程是什麼？跟 managed K8s 的「一鍵升級」差多少？

**使用情境：**
- **為什麼用 kubeadm？** 它是 Kubernetes 官方的「叢集安裝器」，幫你自動處理憑證生成、etcd 初始化、API Server 設定等複雜步驟。手動安裝（"Kubernetes The Hard Way"）需要自己生成幾十個 TLS 憑證。
- **不用會怎樣？** 你可以用 managed K8s（如 EKS/GKE）完全跳過這步。但 OCI Always Free 沒有 managed K8s（OKE 需要付費 worker node），所以 kubeadm 是你唯一的選擇。
- **用了的代價？** 你要自己管理 Control Plane 的可用性（etcd 備份、憑證更新、版本升級）。Managed K8s 這些全部幫你做了。

**情境延伸 — K8s 安裝方式比較：**

| 方案 | 適合場景 | 優點 | 缺點 |
|------|---------|------|------|
| **kubeadm (你的選擇)** | 自管叢集、學習用 | 官方工具、完整 K8s、可客製化 | 要自己管 CP、升級手動、無 HA 內建 |
| **k3s (Rancher)** | 邊緣/IoT、資源受限環境 | 極輕量（單一 binary ~60MB）、內建 SQLite 取代 etcd | 部分功能精簡、不支援所有 K8s API |
| **kind / minikube** | 本機開發/測試 | 秒級啟動、用完即丟 | 僅限單機、不適合生產 |
| **Managed K8s (EKS/GKE/AKS/OKE)** | 生產環境 | CP 全託管、自動升級、SLA 保證 | 按用量收費、黑盒子 CP、vendor lock-in |

> k3s 在你的場景（3 台 ARM VM、資源有限）其實也很適合，但 kubeadm 的學習價值更高。

**驗證指令：**
```bash
ssh oci-cp 'kubectl describe node cp | grep -A5 Taints'   # 查看 CP 的 taint
ssh oci-cp 'kubectl get nodes'                              # 確認所有節點 Ready
ssh oci-cp 'sudo kubeadm token list'                        # 查看 bootstrap tokens
```

**破壞實驗：**
- 實驗 1：在 CP 上加回 taint `ssh oci-cp 'kubectl taint nodes cp node-role.kubernetes.io/control-plane:NoSchedule'` → 觀察新 Pod 是否不再被排程到 CP → 移除 taint 修復
- 實驗 2：`ssh oci-cp 'kubectl delete pod etcd-cp -n kube-system'` → 觀察 static pod 是否自動重建（kubelet 管理）
- ⚠️ 注意：不要刪除 etcd 的資料目錄，只刪 Pod 是安全的（kubelet 會重建 static pod）

**概念連結：**
- → [階段 1（架構）](stage-1-architecture.md)：kubeadm 是把 Layer 1 的 VM 變成 Layer 2 K8s 平台的橋樑
- → [階段 2（節點準備）](stage-2-node-setup.md)：kubeadm init 的前提是 containerd + kernel modules 已就緒
- → [階段 4（網路）](stage-4-networking.md)：kubeadm init 後必須安裝 CNI，否則 Node 永遠 NotReady

**生產環境對照：**
- 學習環境：單 CP + etcd → 生產環境：3 CP 節點 + 3 etcd 節點（或 etcd 跑在 CP 上的 stacked 模式）
- 學習環境：Bootstrap Token 手動複製貼上 → 生產環境：用 cluster-api 或 Terraform 自動化 join 流程
- 學習環境：kubeadm 手動升級 → 生產環境：managed K8s 按鈕升級，或用 GitOps 管理 kubeadm 設定

**Recall Check：**
- Q: `kubeadm init` 做了哪些事？至少說出 3 個步驟
- Q: Bootstrap Token 的格式是什麼？為什麼要設 24 小時過期？
- Q: 什麼是 static pod？跟普通 Pod 的差異？
- Q: 你的 CP 移除了什麼 taint？如果不移除會怎樣？

---

## 學習筆記

（Session 完成後記錄）
