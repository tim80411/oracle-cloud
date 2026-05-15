# 階段 1：K8s 架構全景 ✅

[← 回到方法論](../SKILL.md)

---

**對應文件：**
- `docs/decisions/deployment-architecture-design.md`
- `docs/reference/requirements.md`

**學到的概念：**
- 三層架構：Infrastructure (Terraform) → Platform (kubeadm) → Application (GitOps)
- K8s 核心組件：apiserver、etcd、scheduler、controller-manager、kube-proxy、coredns
- 平台組件：Flannel (CNI)、ingress-nginx、cert-manager、ArgoCD
- 流量路徑：Internet → NLB → ingress-nginx → Service → Pod
- Design Decision：CP 也排程工作負載（Always Free 資源限制下的取捨）

**研究問題（Phase 1）：** ✅ 已完成
- [x] K8s 的「宣告式」管理跟傳統「命令式」部署的根本差異是什麼？
- [x] K8s 的核心組件各自負責什麼？如果某個掛了會發生什麼？
- [x] 在只有 3 台 VM 的環境中，K8s 跟 docker-compose / systemd 相比，overhead 有多大？
- [x] K8s 生態中「必裝」vs「選裝」的組件怎麼分？（CNI 必裝、Ingress 選裝？）

**使用情境：**
- **為什麼要用 K8s？** 你有 3 台 VM 要跑多個服務。沒有 K8s，你要手動 SSH 部署、手動管理哪台跑什麼、手動處理服務掛掉後重啟。K8s 把這些全部自動化：你只描述「期望狀態」，它負責實現。
- **不用會怎樣？** 用 docker-compose 或直接跑 binary 也能部署。但隨著服務增多，你會花越來越多時間在「運維」而非「開發」。跨機器部署、服務發現、自動重啟、滾動更新都要自己寫腳本。
- **用了的代價？** K8s 本身消耗資源（你的 27 個 Pod 裡只有 2 個是應用），學習曲線陡峭，小規模場景可能過度工程。你的集群 25 個平台 Pod vs 2 個應用 Pod 就是這個代價的直觀體現。

**情境延伸 — 容器編排方案比較：**

| 方案 | 適合場景 | 優點 | 缺點 |
|------|---------|------|------|
| **K8s (你的選擇)** | 多節點、多服務、需要自動化運維 | 生態系最完整、業界標準、自動排程/自癒/擴縮 | 資源開銷大、學習曲線陡、小規模 overkill |
| **Docker Compose** | 單機、開發/測試環境 | 極簡設定、幾乎零開銷 | 不支援跨機器、無自動重啟策略、無服務發現 |
| **Docker Swarm** | 小型多節點、想要比 Compose 多一點 | 設定簡單、Docker 內建 | 社群萎縮、功能有限、缺少 Ingress 生態 |
| **Nomad (HashiCorp)** | 混合負載（容器 + 非容器） | 輕量、支援 VM/binary/container | 生態系小、缺少原生 service mesh |
| **直接跑 systemd** | 極簡、1-2 個服務 | 零額外依賴、最省資源 | 完全手動運維、無法自動排程 |

> 你的選擇合理：用 K8s 是因為目標是學習 + 建立可擴展基礎，而非追求最小開銷。

**驗證指令：**
```bash
ssh oci-cp 'kubectl get nodes -o wide'          # 查看節點
ssh oci-cp 'kubectl get pods -A'                 # 查看所有組件
```

**破壞實驗：** ✅ 已完成（階段 1 為概覽，無適合的破壞實驗）

**概念連結：**
- → [階段 2（節點準備）](stage-2-node-setup.md)：理解為什麼 K8s 需要 containerd、kernel modules 等前置條件
- → [階段 4（網路）](stage-4-networking.md)：流量路徑圖中的每一跳都對應一個網路概念
- → [階段 6（排錯）](stage-6-troubleshooting.md)：架構全景是排錯時「從外到內逐層排查」的地圖

**生產環境對照：**
- 學習環境：CP 也跑工作負載（移除 taint） → 生產環境：CP 專用，絕不跑業務 Pod
- 學習環境：單 CP 節點 → 生產環境：3 CP + etcd cluster（HA）
- 學習環境：27 個 Pod 就是全部 → 生產環境：可能有數千個 Pod，需要 namespace 做資源隔離和 RBAC

**Recall Check：**
- Q: K8s 的 4 個核心 Control Plane 組件是什麼？各負責什麼？
- Q: 一個 HTTP 請求從瀏覽器到你的 echo-server Pod，經過哪些元件？
- Q: 為什麼你的 25 個平台 Pod vs 2 個應用 Pod 不算「浪費」？
- Q: 宣告式（Declarative）跟命令式（Imperative）管理的根本差異？

---

## 學習筆記

### Session 1 — 架構全景
- K8s 的核心價值：自動化容器的部署、擴縮、網路路由
- 三層分離讓每一層可以獨立重建而不影響其他層
- 你的集群有 27 個 Pod 在運作，但只有 2 個是你的應用（echo-server、apple-crawler），其餘都是平台組件
