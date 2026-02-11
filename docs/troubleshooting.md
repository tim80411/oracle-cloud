# Troubleshooting Guide

常見問題與排查指南。

## 目錄

- [OCI 帳號與資源](#oci-帳號與資源)
  - [ARM Instance "Out of capacity" 錯誤](#arm-instance-out-of-capacity-錯誤)
  - [API Key 驗證失敗](#api-key-驗證失敗)
  - [Permission Denied 權限不足](#permission-denied-權限不足)
- [NLB 相關](#nlb-相關)
  - [NLB Backend 顯示不健康](#nlb-backend-顯示不健康)
  - [NLB Health Check OK 但外部連不上](#nlb-health-check-ok-但外部連不上)
  - [NLB Reserved IP 綁定失效](#nlb-reserved-ip-綁定失效)
- [iptables 相關](#iptables-相關)
  - [VCN 內部可通但外部流量被擋](#vcn-內部可通但外部流量被擋)
- [Ingress 相關](#ingress-相關)
  - [Ingress Controller 未監聽 80/443](#ingress-controller-未監聽-80443)

---

## OCI 帳號與資源

### ARM Instance "Out of capacity" 錯誤

**症狀：** `terraform apply` 建立 ARM instance 時出現 `Out of host capacity` 錯誤。

**排查步驟：**

```bash
# 確認錯誤訊息
tf-oci apply 2>&1 | grep -i capacity
```

**原因：** ARM A1.Flex 是 Always Free 熱門資源，該 Availability Domain 的實體主機已滿。

**解法：**
- 不同時段重試（清晨可用性較高）
- 寫腳本自動重試
- 如果 region 有多個 Availability Domain，嘗試不同的 AD

---

### API Key 驗證失敗

**症狀：** Terraform 或 OCI CLI 操作時出現 `401 NotAuthenticated` 或 `SignatureDoesNotMatch` 錯誤。

**排查步驟：**

```bash
# 1. 確認本地 key fingerprint
openssl rsa -pubout -outform DER -in ~/.ssh/oci_api_key.pem | openssl md5 -c

# 2. 比對 OCI Console 上的 fingerprint
#    Profile icon → User Settings → API Keys

# 3. 確認 ~/.oci/config 中的 fingerprint、tenancy、user OCID 是否正確
cat ~/.oci/config
```

**常見原因：**
- `~/.oci/config` 中的 fingerprint 與 OCI Console 上的不一致
- API Key 過期或被刪除
- `key_file` 路徑指向錯誤的 PEM 檔案

---

### Permission Denied 權限不足

**症狀：** OCI API 回傳 `404 NotAuthorizedOrNotFound` 或 `403 Forbidden`。

**排查步驟：**

```bash
# 1. 確認目前的 user OCID
grep user ~/.oci/config

# 2. 在 OCI Console 確認 IAM 政策
#    Identity & Security → Policies
```

**解法：** 確認 user 有適當的 IAM 政策。Always Free 使用 root compartment 時，tenancy administrator 應有完整權限。如果是新建的 user，需要加入 Administrators group 或設定對應的 policy statement。

---

## NLB 相關

### NLB Backend 顯示不健康

**症狀：** OCI Console 中 NLB Backend Set 的 Health Status 顯示 Critical。

**排查步驟：**

```bash
# 1. SSH 進入 Backend 節點，確認目標 port 是否有服務監聽
ss -tlnp | grep -E ':80|:443'

# 2. 本地測試服務是否正常回應
curl -s -o /dev/null -w '%{http_code}' http://localhost:80

# 3. 用 OCI CLI 查看 Health Check 狀態
oci nlb backend-set-health get \
  --network-load-balancer-id <nlb-ocid> \
  --backend-set-name <backend-set-name>
```

**常見原因：**
- Ingress Controller 使用 NodePort（高位 port）而非 HostPort（80/443），見 [Ingress Controller 未監聽 80/443](#ingress-controller-未監聽-80443)
- K8s 叢集尚未初始化，沒有服務運行
- iptables 阻擋了 Health Check 流量

---

### NLB Health Check OK 但外部連不上

**症狀：** `oci nlb backend-set-health get` 顯示 `"status": "OK"`，但 `curl http://<NLB-IP>` 超時。

**排查步驟：**

```bash
# 1. 先測試直連 Backend 節點（繞過 NLB）
curl -sv --connect-timeout 5 http://<control-plane-public-ip>

# 2. 在 Backend 節點上用 tcpdump 抓包，同時從外部 curl NLB
#    終端 1（Backend 節點上）：
sudo tcpdump -i enp0s6 'port 80' -n -c 10
#    終端 2（外部）：
curl http://<nlb-public-ip>

# 3. 觀察 tcpdump 結果
#    - 如果只有 SYN→ACK→FIN：只有 Health Check，沒有真實流量到達
#    - 如果有 PUSH 封包：流量有到達，問題在應用層

# 4. 檢查 Reserved IP 綁定狀態
oci network public-ip get \
  --public-ip-id <reserved-ip-ocid> \
  --query 'data.{"ip": "ip-address", "state": "lifecycle-state", "assigned-to": "assigned-entity-type"}'
```

**常見原因：**
- Reserved IP 綁定狀態不一致，見 [NLB Reserved IP 綁定失效](#nlb-reserved-ip-綁定失效)
- iptables 擋住外部流量（Health Check 用 NLB Private IP 所以通過，但 preserve-source 模式下真實流量被擋），見 [VCN 內部可通但外部流量被擋](#vcn-內部可通但外部流量被擋)

---

### NLB Reserved IP 綁定失效

**症狀：** NLB 顯示 Public IP 已綁定，但 Reserved IP 側顯示 `"assigned-id": null, "state": "AVAILABLE"`。外部流量超時。

**確認方式：**

```bash
# NLB 側 — 顯示有 reserved-ip
oci nlb network-load-balancer get \
  --network-load-balancer-id <nlb-ocid> \
  --query 'data."ip-addresses"'

# IP 側 — 顯示 AVAILABLE（未綁定）
oci network public-ip get \
  --public-ip-id <reserved-ip-ocid> \
  --query 'data.{"state": "lifecycle-state", "assigned-to": "assigned-entity-type"}'
```

**解法：** 用 Terraform `-target` 重建 NLB（需先加 lifecycle 保護 VM）：

```bash
# 1. 保護 VM 不被重建（在 compute.tf 中加入 lifecycle ignore_changes）
# 2. Taint NLB
terraform taint oci_network_load_balancer_network_load_balancer.k8s

# 3. 只重建 NLB 相關資源
tf-oci apply \
  -target=oci_network_load_balancer_network_load_balancer.k8s \
  -target=oci_network_load_balancer_backend_set.ingress \
  -target=oci_network_load_balancer_backend_set.ingress_https \
  -target=oci_network_load_balancer_backend.control_plane_http \
  -target=oci_network_load_balancer_backend.control_plane_https \
  -target=oci_network_load_balancer_listener.http \
  -target=oci_network_load_balancer_listener.https \
  -auto-approve
```

---

## iptables 相關

### VCN 內部可通但外部流量被擋

**症狀：** 從 VCN 內部（如其他 Node）可連到 80/443，但外部（如本機 curl）被擋。Security List 已開放。

**確認方式：**

```bash
sudo iptables -L INPUT -n --line-numbers
```

檢查是否有類似這樣的規則順序：

```
11   ACCEPT     0    --  10.0.0.0/24     0.0.0.0/0       ← VCN 內部放行
12   REJECT     0    --  0.0.0.0/0       0.0.0.0/0       ← 其他全擋
```

**背景：** OCI Ubuntu 預設有 iptables REJECT 規則。Security List 是 VCN 層的防火牆，iptables 是 OS 層的防火牆，兩者獨立運作，都要放行才能通。

**解法：** 在 REJECT 規則之前插入 ACCEPT：

```bash
# 找到 REJECT 規則的行號（假設是 12）
sudo iptables -I INPUT 12 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 12 -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

記得同步更新 `terraform/cloud-init/k8s-control-plane.yaml` 以持久化。

---

---

## Ingress 相關

### Ingress Controller 未監聽 80/443

**症狀：** Ingress Controller Pod 正常 Running，但 Node 的 80/443 port 沒有服務監聽。

**確認方式：**

```bash
# 檢查 Service 類型
kubectl get svc -n ingress-nginx
# 如果顯示 NodePort 80:3xxxx/TCP — 就是這個問題

# 檢查 Pod 的 port 配置
kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.containers[0].ports}' | jq
# 確認是否有 hostPort 欄位
```

**背景：** Kubernetes NodePort 預設使用高位 port（30000-32767）。在裸機/VM 環境中，如果 NLB 或外部流量需要直接連到 80/443，必須使用 hostPort 模式。

**解法：** Patch Deployment 加入 hostPort：

```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/ports/0/hostPort", "value": 80},
  {"op": "add", "path": "/spec/template/spec/containers/0/ports/1/hostPort", "value": 443}
]'
```

驗證：

```bash
# 等待 rollout 完成
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx

# 確認 port 回應
curl -s -o /dev/null -w '%{http_code}' http://localhost:80
# 預期：404（Ingress Controller 正常運行，無匹配規則）
```
