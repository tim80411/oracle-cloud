# NLB 連線問題排查記錄

**日期：** 2026-02-10
**狀態：** 已解決

## 問題描述

NLB 的 Backend Health Check 顯示不健康，外部流量無法透過 NLB Public IP (<NLB_PUBLIC_IP>) 到達 Ingress Controller。

---

## 問題 1：Ingress Controller 使用 NodePort 而非 HostPort

### 症狀

NLB Health Check 對 port 80/443 檢查失敗，Backend 顯示不健康。

### 確認方式

SSH 進入 Control Plane 檢查 Ingress Controller 的 Service 類型和 port 監聽狀態：

```bash
# 檢查 Ingress Service 類型
kubectl get svc -n ingress-nginx
# 結果：NodePort 80:32011/TCP, 443:30294/TCP

# 檢查 Node 上是否有服務監聽 80/443
ss -tlnp | grep -E ':80|:443'
# 結果：無輸出，代表沒有服務監聽
```

### 根因

ingress-nginx 以 `NodePort` 模式安裝，服務暴露在高位 port（32011/30294），而非直接綁定 Node 的 80/443。NLB 的 Health Check 和 Backend 都設定指向 port 80/443，自然連不到。

### 解法

Patch ingress-nginx Deployment，加入 hostPort 讓 Ingress Controller 直接綁定 Node 的 80/443：

```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/ports/0/hostPort", "value": 80},
  {"op": "add", "path": "/spec/template/spec/containers/0/ports/1/hostPort", "value": 443}
]'
```

驗證：

```bash
kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.containers[0].ports}' | jq
# 確認 hostPort: 80 和 hostPort: 443 出現

curl -s -o /dev/null -w '%{http_code}' http://localhost:80
# 結果：404（正確，代表 Ingress Controller 正在回應）
```

---

## 問題 2：iptables 阻擋外部流量到 port 80/443

### 症狀

NLB Health Check 通過（因為 NLB 用 Private IP 10.0.0.85 發送，在 VCN CIDR 內），但外部用戶流量無法到達。

### 確認方式

檢查 iptables INPUT chain：

```bash
sudo iptables -L INPUT -n --line-numbers
```

發現規則順序：

```
11   ACCEPT     0    --  10.0.0.0/24     0.0.0.0/0       ← VCN 內部放行
12   REJECT     0    --  0.0.0.0/0       0.0.0.0/0       ← 其他全部拒絕
```

OCI Ubuntu 預設有 iptables REJECT 規則。當 NLB 設定 `is-preserve-source-destination: true` 時，真實用戶流量的來源 IP 不在 10.0.0.0/24 範圍內，會被 REJECT。

### 根因

OCI Ubuntu 預設 iptables 有 catch-all REJECT 規則。cloud-init 只開放了 VCN 內部 (10.0.0.0/24) 和 Pod 網路 (10.244.0.0/16)，沒有開放 80/443 給外部流量。

### 解法

在 REJECT 規則之前插入 ACCEPT 規則：

```bash
sudo iptables -I INPUT 12 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 12 -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

同步更新 `terraform/cloud-init/k8s-control-plane.yaml` 以持久化規則。

---

## 問題 3：NLB Reserved IP 綁定狀態不一致

### 症狀

iptables 修復後，直接 curl Control Plane Public IP 正常回應 200，但 curl NLB Public IP 持續超時。NLB Backend Health 顯示 OK。

### 確認方式

1. 在 CP 上用 tcpdump 抓包，同時從外部 curl NLB：

```bash
# CP 上
sudo tcpdump -i enp0s6 'port 80' -n -c 10

# 外部
curl http://<NLB_PUBLIC_IP>
```

結果：只抓到 Health Check 封包（SYN → ACK → FIN），沒有真實用戶流量到達。

2. 檢查 Reserved IP 的綁定狀態：

```bash
oci network public-ip get --public-ip-id <reserved-ip-ocid> \
  --query 'data.{"ip": "ip-address", "state": "lifecycle-state", "assigned-to": "assigned-entity-type"}'
```

結果：

```json
{
  "assigned-id": null,
  "assigned-to": null,
  "ip": "<NLB_PUBLIC_IP>",
  "state": "AVAILABLE"
}
```

NLB 側認為 Reserved IP 已綁定，但 IP 側顯示未綁定 (`AVAILABLE`)，狀態不一致。

### 根因

OCI NLB 和 Reserved IP 之間的綁定關係「斷裂」。NLB 記錄著此 IP，但 IP 端不認為自己被綁定。外部流量無法被路由到 NLB。

### 解法

使用 Terraform 重建 NLB：

```bash
# 1. 先加 lifecycle ignore_changes 保護 VM（cloud-init 修改會觸發 VM 重建）
# compute.tf 中為 control_plane 和 worker 加入：
lifecycle {
  ignore_changes = [metadata]
}

# 2. Taint NLB
terraform taint oci_network_load_balancer_network_load_balancer.k8s

# 3. 用 -target 只重建 NLB 相關資源，不動 VM
AWS_PROFILE=oci terraform apply \
  -target=oci_network_load_balancer_network_load_balancer.k8s \
  -target=oci_network_load_balancer_backend_set.ingress \
  -target=oci_network_load_balancer_backend_set.ingress_https \
  -target=oci_network_load_balancer_backend.control_plane_http \
  -target=oci_network_load_balancer_backend.control_plane_https \
  -target=oci_network_load_balancer_listener.http \
  -target=oci_network_load_balancer_listener.https \
  -auto-approve
```

重建後 Reserved IP 正確綁定到新 NLB，外部流量正常通過。

---

## 排查過程中的額外發現

### OCI metadata 修改會 force replace VM

OCI provider 的 `oci_core_instance` 資源中，`metadata`（含 `user_data`）是 ForceNew 欄位。修改 cloud-init 內容會觸發 VM 銷毀重建。

**防護措施：** 在 compute.tf 中加入 `lifecycle { ignore_changes = [metadata] }`，讓 cloud-init 修改只影響未來新建的 VM。

### OCI NLB is-preserve-source-destination

- `true`：保留客戶端原始 IP，Ingress 可看到真實 IP（需要 iptables 開放 80/443）
- `false`（預設）：使用 NLB 的 Private IP 轉發，Ingress 看到的都是 NLB IP

目前設定為 `false`（OCI 預設值），但 iptables 已預先開放 80/443 為未來切換做準備。

---

## 最終驗證

```bash
# NLB HTTP
curl -s -o /dev/null -w '%{http_code}' http://<NLB_PUBLIC_IP>
# 200

# Control Plane 直連
curl -s -o /dev/null -w '%{http_code}' http://<CP_PUBLIC_IP>
# 200
```

## 修改的檔案

| 檔案 | 修改內容 |
|------|---------|
| `terraform/cloud-init/k8s-control-plane.yaml` | 新增 iptables ACCEPT 規則 (port 80/443) |
| `terraform/compute.tf` | 新增 `lifecycle { ignore_changes = [metadata] }` 給 control_plane 和 worker |
