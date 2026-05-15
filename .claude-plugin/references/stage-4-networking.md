# 階段 4：K8s 網路模型 ⬜

[← 回到方法論](../SKILL.md) | [← 上一階段](stage-3-kubeadm.md) | [下一階段 →](stage-5-ingress-tls.md)

---

**對應文件：**
- `docs/learning/logging/layer2-installation-report.md` (網路部分)

**預計學習概念：**
- K8s 三層網路：Node Network / Pod Network / Service Network
- Flannel CNI：VXLAN overlay 如何讓跨 Node 的 Pod 互通
- kube-proxy：iptables NAT 規則如何實現 Service → Pod 路由
- ClusterIP vs NodePort vs LoadBalancer 的差異
- CoreDNS：叢集內 DNS 解析（`<service>.<namespace>.svc.cluster.local`）

**研究問題（Phase 1）：**
- [ ] K8s 網路模型的「三大保證」是什麼？（Pod-to-Pod、Pod-to-Service、External-to-Service）
- [ ] VXLAN overlay 的封裝機制具體怎麼運作？一個封包從 Node A 的 Pod 到 Node B 的 Pod 經過哪些步驟？
- [ ] kube-proxy 的 iptables 模式 vs IPVS 模式差在哪？什麼時候該切換？
- [ ] ClusterIP、NodePort、LoadBalancer 三種 Service 類型的實際 iptables 規則長什麼樣？
- [ ] CoreDNS 的 `<service>.<namespace>.svc.cluster.local` 解析邏輯和 search domain 設定

**使用情境：**
- **為什麼需要 CNI（Flannel）？** K8s 要求「任何 Pod 可以直接用 IP 跟任何 Pod 通信」，但 Pod 分散在不同 Node 上，不同 Node 有不同的子網。CNI 建立 overlay network，讓跨 Node 的 Pod 看起來像在同一個網路。
- **不裝會怎樣？** `kubeadm init` 後 Node 狀態會一直是 `NotReady`，CoreDNS Pod 會卡在 `Pending`，因為沒有網路插件幫 Pod 分配 IP。
- **用了的代價？** Overlay network 有封裝/解封裝的開銷（VXLAN 額外 50 bytes header），跨 Node 流量多一層封裝。在你的場景（同一 VCN 內 3 台 VM）影響極小。

**情境延伸 — CNI 插件比較：**

| 方案 | 適合場景 | 優點 | 缺點 |
|------|---------|------|------|
| **Flannel (你的選擇)** | 簡單環境、學習用 | 極簡設定、穩定可靠、資源佔用低 | 無 Network Policy 支援、無加密 |
| **Calico** | 需要 Network Policy 的生產環境 | 支援 Network Policy、可用 BGP 避免 overlay | 設定較複雜、資源佔用較高 |
| **Cilium** | 高效能、觀測性需求 | eBPF 核心（繞過 iptables）、內建觀測工具 Hubble | 需要較新 kernel、資源佔用最高 |
| **Weave Net** | 多雲/跨雲環境 | 內建加密、自動 mesh | 效能較差、社群維護趨緩 |

> Flannel 對你的 Always Free 環境是最佳選擇：最省資源、最簡單。如果未來需要 Network Policy（限制 Pod 間通信），可以考慮 Calico。

**驗證指令：**
```bash
ssh oci-cp 'kubectl get pods -o wide -A | head -20'        # 查看 Pod IP 分佈
ssh oci-cp 'kubectl get svc -A'                             # 查看所有 Service
ssh oci-cp 'ip route | grep flannel'                        # 查看 Flannel 路由
```

**破壞實驗：**
- 實驗 1：刪除一個 Node 上的 Flannel Pod `ssh oci-cp 'kubectl delete pod -n kube-flannel -l app=flannel --field-selector spec.nodeName=w1'` → 觀察 w1 上的 Pod 是否失去跨 Node 連線 → DaemonSet 會自動重建
- 實驗 2：建一個臨時 Pod 測試跨 Node 通信 `kubectl run test --image=busybox --rm -it -- wget -qO- <另一個 Node 上 Pod 的 IP>` → 確認 CNI 正常
- ⚠️ 注意：Flannel DaemonSet 會自動重建 Pod，但中間可能有幾秒的網路中斷

**概念連結：**
- → [階段 2（節點準備）](stage-2-node-setup.md)：`br_netfilter` 和 `ip_forward` 是 Pod 網路的底層基礎
- → [階段 5（Ingress）](stage-5-ingress-tls.md)：Ingress Controller 的流量最終也要經過 Service → Pod 的網路路徑
- → [階段 6（排錯）](stage-6-troubleshooting.md)：NLB 問題的根因之一就是網路層的 iptables 規則

**生產環境對照：**
- 學習環境：Flannel（無 Network Policy）→ 生產環境：Calico 或 Cilium（強制 Network Policy，限制 Pod 間通信）
- 學習環境：kube-proxy iptables 模式 → 生產環境：大規模叢集用 IPVS 模式（效能更好）
- 學習環境：所有 Pod 在同一子網 → 生產環境：可能用 multi-tenant network isolation

**Recall Check：**
- Q: K8s 網路模型的三大保證是什麼？
- Q: Flannel 的 VXLAN 封裝做了什麼？封包從 Node A 到 Node B 經過哪些步驟？
- Q: ClusterIP、NodePort、LoadBalancer 三種 Service 的差異？
- Q: `10.244.0.0/16` 和 `10.96.0.0/12` 分別是什麼網段？

---

## 學習筆記

（Session 完成後記錄）
