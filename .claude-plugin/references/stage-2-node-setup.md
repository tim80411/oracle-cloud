# 階段 2：節點準備 & 容器運行時 ⬜

[← 回到方法論](../SKILL.md) | [← 上一階段](stage-1-architecture.md) | [下一階段 →](stage-3-kubeadm.md)

---

**對應文件：**
- `docs/guides/logging/layer2-manual-setup.md` (Step 1-2)

**預計學習概念：**
- Linux kernel modules：overlay、br_netfilter 的作用
- sysctl 設定：ip_forward、bridge-nf-call-iptables 為什麼必要
- containerd：Container Runtime Interface (CRI) 的角色
- SystemdCgroup：為什麼 containerd 必須使用 systemd cgroup driver
- kubeadm / kubelet / kubectl 的分工

**研究問題（Phase 1）：**
- [ ] overlay 和 br_netfilter 這兩個 kernel module 各做什麼？不載入的話 K8s 的哪個功能會壞？
- [ ] `net.ipv4.ip_forward = 1` 在 K8s 中扮演什麼角色？跟 Pod 跨 Node 通信有什麼關係？
- [ ] Container Runtime Interface (CRI) 是什麼規範？為什麼 K8s 需要這層抽象？
- [ ] cgroup v1 vs cgroup v2 差在哪？為什麼 SystemdCgroup = true 很重要？
- [ ] kubeadm、kubelet、kubectl 三者的關係是什麼？哪些只在安裝時用、哪些持續運行？

**使用情境：**
- **為什麼需要 containerd？** K8s 本身不會運行容器，它需要一個「容器運行時」來實際建立/啟動/停止容器。containerd 就是這個中間層，把 K8s 的「請幫我跑這個 image」翻譯成實際的 Linux namespace/cgroup 操作。
- **不裝會怎樣？** `kubeadm init` 直接報錯失敗，因為 kubelet 找不到 CRI socket。沒有 container runtime = K8s 完全無法運作。
- **用了的代價？** containerd 本身很輕量（比 Docker daemon 省資源），但需要正確設定 cgroup driver 和 kernel modules，設定錯誤會導致 kubelet 啟動失敗或 Pod 無法建立。

**情境延伸 — Container Runtime 比較：**

| 方案 | 適合場景 | 優點 | 缺點 |
|------|---------|------|------|
| **containerd (你的選擇)** | K8s 標準搭配 | 輕量、CNCF 畢業專案、K8s 預設推薦 | 不含 `docker` CLI（需另裝 nerdctl） |
| **Docker Engine** | 開發環境、需要 docker CLI | 開發者熟悉、docker build/push 方便 | K8s 1.24+ 移除 dockershim，多一層抽象（Docker → containerd） |
| **CRI-O** | Red Hat / OpenShift 生態系 | 專為 K8s 設計、最小化攻擊面 | 社群較小、不能獨立於 K8s 使用 |

> Docker Engine 底層其實也是 containerd，K8s 1.24 後移除了 dockershim，直接用 containerd 少一層轉接。

**驗證指令：**
```bash
ssh oci-cp 'lsmod | grep -E "overlay|br_netfilter"'      # 確認 kernel modules
ssh oci-cp 'sysctl net.ipv4.ip_forward'                    # 確認 IP forwarding
ssh oci-cp 'systemctl status containerd'                   # 確認 containerd 狀態
```

**破壞實驗：**
- 實驗 1：`ssh oci-cp 'sudo sysctl net.ipv4.ip_forward=0'` → 觀察 Pod 跨 Node 通信是否中斷 → 改回 `=1` 修復
- 實驗 2：`ssh oci-cp 'sudo systemctl stop containerd'` → 觀察該 Node 上的 Pod 狀態變化（應變為 NotReady）→ `start` 修復
- ⚠️ 注意：在 CP 上停 containerd 會影響所有控制平面組件，建議在 worker 上實驗

**概念連結：**
- → [階段 1（架構）](stage-1-architecture.md)：這些準備工作是 Layer 2 的第一步，讓 VM 從「普通 Linux」變成「K8s 就緒」
- → [階段 3（kubeadm）](stage-3-kubeadm.md)：kernel modules 和 containerd 是 `kubeadm init` 的前置條件，缺一不可
- → [階段 4（網路）](stage-4-networking.md)：`br_netfilter` 和 `ip_forward` 直接影響 Pod 網路能否運作

**生產環境對照：**
- 學習環境：手動安裝 containerd → 生產環境：通常用 Ansible/Puppet 批量配置，或直接用預裝好的 VM image
- 學習環境：手動設定 kernel modules → 生產環境：寫進 machine image (AMI/OCI custom image)，bake 進 golden image
- 學習環境：3 台 VM 手動操作 → 生產環境：數百台 Node 用 cluster-api 或 cloud provider 自動化

**Recall Check：**
- Q: `overlay` kernel module 做什麼？跟容器的 filesystem 有什麼關係？
- Q: 為什麼 `br_netfilter` 對 K8s 網路是必要的？
- Q: containerd 跟 Docker 的關係是什麼？為什麼 K8s 1.24 移除了 dockershim？
- Q: kubelet 在 Node 上的角色是什麼？它跟 kube-apiserver 怎麼溝通？

---

## 學習筆記

（Session 完成後記錄）
