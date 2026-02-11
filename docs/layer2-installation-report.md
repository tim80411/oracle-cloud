# Layer 2 安裝報告：Kubernetes Cluster 手動設置

本報告記錄在 OCI Always Free 環境中手動安裝 Kubernetes 叢集的完整過程，包含遇到的問題、解決方案，以及相關技術概念的深入說明。

## 環境概述

| 項目 | 值 |
|------|-----|
| 平台 | Oracle Cloud Infrastructure (OCI) Always Free |
| 節點 | 1 Control Plane (cp) + 2 Workers (w1, w2) |
| OS | Ubuntu 24.04 ARM |
| K8s 版本 | v1.32.x |
| CNI | Flannel |
| Ingress | ingress-nginx |

---

## 第一部分：節點加入叢集 (kubeadm join)

### 執行的指令

```bash
sudo kubeadm join 10.0.0.3:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --ignore-preflight-errors=SystemVerification
```

### 指令解析

| 參數 | 說明 |
|------|------|
| `10.0.0.3:6443` | Control Plane 的 API Server 地址。6443 是 kube-apiserver 的預設 HTTPS 端口 |
| `--token` | Bootstrap Token，用於節點首次加入時的身份驗證，預設 24 小時過期 |
| `--discovery-token-ca-cert-hash` | CA 憑證的 SHA256 雜湊值，防止中間人攻擊，確保連接到正確的 API Server |
| `--ignore-preflight-errors=SystemVerification` | 跳過系統驗證檢查（ARM 架構有時會觸發誤報） |

### 技術關鍵字深入說明

#### kube-apiserver
Kubernetes 控制平面的核心組件，所有叢集操作都透過它進行：
- 提供 RESTful API 介面
- 驗證和授權請求
- 作為 etcd 的唯一入口
- 預設監聽 6443 端口（HTTPS）

#### Bootstrap Token
一種短期憑證機制，用於：
- 新節點加入叢集時的初始身份驗證
- 格式：`[a-z0-9]{6}.[a-z0-9]{16}`
- 存儲在 `kube-system` namespace 的 Secret 中
- 可用 `kubeadm token list` 查看

#### kubeadm
Kubernetes 官方的叢集安裝工具：
- `kubeadm init`：初始化 Control Plane
- `kubeadm join`：將節點加入叢集
- `kubeadm token`：管理 bootstrap token

---

## 第二部分：網路問題診斷與修復

### 遇到的問題

```
dial tcp 10.0.0.3:6443: connect: no route to host
```

### 診斷過程

#### 1. 測試網路連通性

```bash
nc -zv 10.0.0.3 6443
ping 10.0.0.3
```

| 指令 | 用途 |
|------|------|
| `nc -zv` | netcat 測試 TCP 端口連通性。`-z` 只掃描不傳資料，`-v` 顯示詳細輸出 |
| `ping` | 測試 ICMP 連通性（Layer 3） |

**關鍵理解**：`no route to host` vs `connection refused`
- `no route to host`：封包無法到達目標（路由/防火牆問題）
- `connection refused`：封包到達但無服務監聽（應用層問題）

#### 2. 檢查服務是否監聽

```bash
sudo ss -tlnp | grep 6443
```

| 參數 | 說明 |
|------|------|
| `-t` | 只顯示 TCP |
| `-l` | 只顯示 listening 狀態 |
| `-n` | 顯示數字（不解析主機名） |
| `-p` | 顯示 process 資訊 |

**輸出解讀**：
```
LISTEN 0 4096 *:6443 *:* users:(("kube-apiserver",pid=20698,fd=3))
```
- `*:6443`：監聽所有介面的 6443 端口（正常）
- `127.0.0.1:6443`：只監聽本地（問題）

#### 3. 檢查 iptables 規則

```bash
sudo iptables -L INPUT -n --line-numbers
```

| 參數 | 說明 |
|------|------|
| `-L INPUT` | 列出 INPUT chain 的規則 |
| `-n` | 不解析 IP 為主機名 |
| `--line-numbers` | 顯示規則編號（用於刪除/插入） |

### 發現的問題

OCI Ubuntu 映像預設 iptables 設定：

```
Chain INPUT (policy ACCEPT)
...
8    ACCEPT     tcp  --  0.0.0.0/0  0.0.0.0/0  state NEW tcp dpt:22
9    REJECT     all  --  0.0.0.0/0  0.0.0.0/0  reject-with icmp-host-prohibited
```

**問題**：規則 9 拒絕所有非 SSH 流量。

### 修復指令

```bash
# 允許 VCN 內部流量
sudo iptables -I INPUT 9 -s 10.0.0.0/24 -j ACCEPT

# 允許 Pod 網段流量
sudo iptables -I INPUT 9 -s 10.244.0.0/16 -j ACCEPT

# 刪除 FORWARD chain 的 REJECT 規則
sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited

# 持久化
sudo netfilter-persistent save
```

| 指令 | 說明 |
|------|------|
| `-I INPUT 9` | 在 INPUT chain 的第 9 個位置**插入**規則 |
| `-s 10.0.0.0/24` | 來源 IP 範圍（VCN 私有子網） |
| `-j ACCEPT` | 動作：接受封包 |
| `-D FORWARD` | 從 FORWARD chain **刪除**規則 |

### 技術關鍵字深入說明

#### iptables Chains
Linux 核心防火牆 Netfilter 的用戶空間工具：

| Chain | 用途 |
|-------|------|
| INPUT | 進入本機的封包 |
| OUTPUT | 從本機發出的封包 |
| FORWARD | 經過本機轉發的封包（路由器行為） |
| PREROUTING | 封包進入路由決策前（NAT 用） |
| POSTROUTING | 封包離開路由決策後（NAT 用） |

#### 為什麼需要 FORWARD chain？
Kubernetes Pod 網路需要節點作為路由器轉發封包：
```
Pod A (10.244.1.5) → Node (FORWARD) → Pod B (10.244.0.3)
```
如果 FORWARD chain 有 REJECT 規則，跨節點的 Pod 通訊會失敗。

#### Kubernetes 網路分層

| 網段 | 用途 | 範例 |
|------|------|------|
| Node Network | 節點實體 IP | 10.0.0.0/24 |
| Pod Network (CIDR) | CNI 分配給 Pod 的 IP | 10.244.0.0/16 |
| Service Network | ClusterIP 虛擬 IP | 10.96.0.0/12 |

**重要**：Service IP 是純 iptables NAT 規則，不會出現在封包的 source IP 中。

---

## 第三部分：Flannel CNI

### 技術關鍵字深入說明

#### CNI (Container Network Interface)
容器網路的標準介面規範：
- 定義如何為容器配置網路
- 常見實現：Flannel、Calico、Cilium、Weave
- 配置檔位於 `/etc/cni/net.d/`

#### Flannel
簡單的 Layer 3 overlay 網路：
- 使用 VXLAN 封裝跨節點封包
- 每個節點分配一個 `/24` 子網（如 10.244.0.0/24、10.244.1.0/24）
- 透過 `flannel.1` 虛擬介面處理 overlay 封包

#### 檢查 Flannel 狀態

```bash
# 查看 Flannel pods
kubectl get pods -n kube-flannel -o wide

# 查看節點的 Pod 子網分配
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'

# 查看路由表
ip route | grep 10.244

# 查看 flannel.1 介面
ip addr show flannel.1
```

**正常輸出範例**：
```
10.244.0.0/24 dev cni0 proto kernel scope link src 10.244.0.1
10.244.1.0/24 via 10.244.1.0 dev flannel.1 onlink
10.244.2.0/24 via 10.244.2.0 dev flannel.1 onlink
```

---

## 第四部分：kube-proxy 與 Service

### 技術關鍵字深入說明

#### kube-proxy
每個節點上運行的網路代理，實現 Kubernetes Service 抽象：
- 監聽 API Server 的 Service 和 Endpoint 變化
- 維護 iptables/IPVS 規則
- 實現 ClusterIP、NodePort、LoadBalancer 類型的 Service

#### Service 類型

| 類型 | 說明 |
|------|------|
| ClusterIP | 叢集內部 IP，只能從叢集內訪問 |
| NodePort | 在每個節點上開放固定端口 |
| LoadBalancer | 雲端負載均衡器（整合雲平台） |
| ExternalName | DNS CNAME 別名 |

#### 檢查 kube-proxy 規則

```bash
# 查看 KUBE-SERVICES chain
sudo iptables -t nat -L KUBE-SERVICES -n

# 查看特定 Service 的規則
sudo iptables -t nat -L KUBE-SVC-NPX46M4PTMTKRN6Y -n
```

**Service IP 解析流程**：
```
Pod 請求 10.96.0.1:443 (kubernetes service)
    ↓ DNAT (kube-proxy iptables)
實際連接 10.0.0.3:6443 (API Server endpoint)
```

---

## 第五部分：ingress-nginx 安裝

### 執行的指令

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml
```

### 建立的資源

| 資源類型 | 名稱 | 用途 |
|----------|------|------|
| Namespace | ingress-nginx | 隔離 ingress 相關資源 |
| Deployment | ingress-nginx-controller | Nginx 反向代理控制器 |
| Service | ingress-nginx-controller | NodePort 暴露 80/443 |
| IngressClass | nginx | 定義 Ingress 使用的控制器 |
| Job | ingress-nginx-admission-create | 建立 webhook 憑證 |
| ValidatingWebhookConfiguration | ingress-nginx-admission | 驗證 Ingress 資源 |

### 技術關鍵字深入說明

#### Ingress
Kubernetes 的 HTTP/HTTPS 路由規則：
- 將外部請求路由到內部 Service
- 支援基於 host/path 的路由
- 支援 TLS 終止

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

#### Ingress Controller
實現 Ingress 規則的實際組件：
- 監聽 Ingress 資源變化
- 配置反向代理（Nginx、HAProxy、Traefik 等）
- ingress-nginx 使用 Nginx 作為代理

#### Admission Webhook
Kubernetes 的資源驗證/修改機制：
- ValidatingWebhook：驗證資源是否符合規則
- MutatingWebhook：自動修改資源
- ingress-nginx 使用它來驗證 Ingress 配置正確性

---

## 第六部分：cert-manager 安裝

### 執行的指令

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.3/cert-manager.yaml
```

### 建立的資源

| 資源類型 | 名稱 | 用途 |
|----------|------|------|
| Namespace | cert-manager | 隔離憑證管理資源 |
| Deployment | cert-manager | 主控制器，處理 Certificate 資源 |
| Deployment | cert-manager-cainjector | 注入 CA 到 webhook |
| Deployment | cert-manager-webhook | 驗證 cert-manager 資源 |
| CRD | Certificate, Issuer, ClusterIssuer 等 | 自定義資源類型 |

### ClusterIssuer 設定

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 技術關鍵字深入說明

#### cert-manager
Kubernetes 原生的憑證管理控制器：
- 自動簽發和更新 TLS 憑證
- 支援多種 Issuer（Let's Encrypt、Vault、自簽等）
- 與 Ingress 整合，自動配置 TLS

#### ACME (Automatic Certificate Management Environment)
Let's Encrypt 使用的協議：
- 自動化 DV (Domain Validation) 憑證簽發
- 支援 HTTP-01 和 DNS-01 驗證方式

| 驗證方式 | 原理 | 使用場景 |
|----------|------|----------|
| HTTP-01 | 在 `/.well-known/acme-challenge/` 放置驗證檔案 | 有公網 HTTP 訪問 |
| DNS-01 | 在 DNS 添加 TXT 記錄 | wildcard 憑證、無公網 HTTP |

#### Issuer vs ClusterIssuer
- **Issuer**：Namespace 範圍，只能在同 namespace 使用
- **ClusterIssuer**：叢集範圍，所有 namespace 都能使用

### 檢查憑證狀態

```bash
# 查看 ClusterIssuer
kubectl get clusterissuer

# 查看 Certificate
kubectl get certificate -A

# 查看憑證詳情
kubectl describe certificate <name> -n <namespace>

# 查看 ACME 訂單狀態
kubectl get order -A
kubectl get challenge -A
```

---

## 第七部分：除錯技巧總結

### 網路除錯

```bash
# 測試 Pod 網路
kubectl run debug --image=busybox --rm -it --restart=Never -- sh

# 在 Pod 內測試
ping <node-ip>
nslookup kubernetes.default
wget -qO- https://10.96.0.1:443/healthz
```

### 日誌查看

```bash
# kubelet 日誌
sudo journalctl -u kubelet -f

# Pod 日誌
kubectl logs <pod-name> -n <namespace>

# 系統組件日誌
kubectl logs -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-flannel -l app=flannel
```

### kubeadm 詳細輸出

```bash
kubeadm join ... -v=5  # trace 級別日誌
```

| 級別 | 說明 |
|------|------|
| -v=1 | 基本資訊 |
| -v=2 | 穩定狀態資訊 |
| -v=4 | Debug 級別 |
| -v=5 | Trace 級別（推薦除錯用） |

---

## 總結：OCI Ubuntu 映像的 iptables 問題

### 問題根因

OCI 官方 Ubuntu 映像預設啟用嚴格的 iptables 規則：

| Chain | 預設行為 | 影響 |
|-------|----------|------|
| INPUT | 只允許 SSH，其他 REJECT | 節點間通訊失敗 |
| FORWARD | REJECT 所有轉發 | Pod 跨節點通訊失敗 |

### 解決方案

```bash
# INPUT: 允許 VCN 和 Pod 網段
iptables -I INPUT 9 -s 10.0.0.0/24 -j ACCEPT
iptables -I INPUT 9 -s 10.244.0.0/16 -j ACCEPT

# FORWARD: 刪除 REJECT 規則
iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited

# 持久化
netfilter-persistent save
```

### 學到的教訓

1. **多層防火牆**：雲端環境有 Security List（雲端層）和 iptables（OS 層），兩層都要檢查
2. **錯誤訊息解讀**：`no route to host` 指向路由/防火牆問題，`connection refused` 指向應用層問題
3. **Kubernetes 網路分層**：理解 Node/Pod/Service 三層網路對除錯至關重要
4. **FORWARD chain**：CNI 依賴封包轉發，FORWARD chain 的 REJECT 規則會破壞 Pod 網路
