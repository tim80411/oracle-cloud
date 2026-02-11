# Layer 3 GitOps Setup Guide

Layer 3 使用 ArgoCD 的 App-of-Apps pattern，從 private Git repo 自動同步 K8s manifests 到集群。

## Architecture

```
GitHub (private)                    K8s Cluster
┌─────────────────┐                ┌──────────────────────┐
│ k8s-apps repo   │   SSH key      │ ArgoCD               │
│                 │ ◄──────────── │                      │
│ argocd/         │   auto-sync    │ app-of-apps (root)   │
│   app-of-apps   │ ──────────► │   └─ echo-server App │
│   echo-server   │                │                      │
│ apps/           │                │ echo-server ns       │
│   echo-server/  │ ──────────► │   ├─ Deployment      │
│     deploy/svc  │                │   ├─ Service         │
│     ingress     │                │   └─ Ingress         │
└─────────────────┘                └──────────────────────┘
```

**Repo 分離策略：**
- `oracle-cloud` (public) — Infra/Platform 設定，可分享讓他人建自己的 OCI K8s
- `k8s-apps` (private) — 應用程式 manifests，不公開

## Prerequisites

- ArgoCD 已在集群上運行（Layer 2 `init-control-plane.sh` 完成）
- DNS 設定在 Cloudflare（或其他 DNS provider）
- `gh` CLI 已登入

## Step 1: 建立 Private Repo

```bash
gh repo create k8s-apps --private \
  --description "Private Kubernetes application manifests for ArgoCD GitOps" \
  --clone

# 建立基本結構
cd k8s-apps
mkdir -p apps/
# 加 README.md
git add -A && git commit -m "Initial repo structure" && git push -u origin main
```

## Step 2: 產生 SSH Deploy Key

在控制平面上產生專用 key（不設 passphrase）：

```bash
ssh oci-cp 'ssh-keygen -t ed25519 -C "argocd-deploy-key" -f ~/.ssh/argocd-deploy-key -N ""'
ssh oci-cp 'cat ~/.ssh/argocd-deploy-key.pub'
```

Key 存放：`/home/ubuntu/.ssh/argocd-deploy-key`（控制平面）

## Step 3: 加到 GitHub Deploy Keys

```bash
# 把 public key 加到 repo（read-only）
gh repo deploy-key add - --repo <user>/k8s-apps --title "argocd-deploy-key" <<< "ssh-ed25519 ..."

# 驗證
gh repo deploy-key list --repo <user>/k8s-apps
```

## Step 4: ArgoCD 註冊 Private Repo

在控制平面上建立帶 ArgoCD label 的 K8s Secret：

```bash
ssh oci-cp 'bash -s' << 'REMOTE_SCRIPT'
cat > /tmp/argocd-repo-secret.yaml << YAML
apiVersion: v1
kind: Secret
metadata:
  name: k8s-apps-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: git@github.com:<user>/k8s-apps.git
  sshPrivateKey: |
$(sed 's/^/    /' ~/.ssh/argocd-deploy-key)
YAML
kubectl apply -f /tmp/argocd-repo-secret.yaml
rm /tmp/argocd-repo-secret.yaml
REMOTE_SCRIPT
```

驗證：
```bash
ssh oci-cp 'kubectl get secret k8s-apps-repo -n argocd -o jsonpath="{.data.sshPrivateKey}" | base64 -d | head -1'
# -----BEGIN OPENSSH PRIVATE KEY-----
```

## Step 5: 部署測試應用 + Ingress

### 建立 echo-server

```
apps/echo-server/
├── namespace.yaml    # Namespace
├── deployment.yaml   # nginx:alpine, 極小 resources (10m CPU / 16Mi)
├── service.yaml      # ClusterIP port 80
└── ingress.yaml      # app.<domain>/echo, TLS via cert-manager
```

**Ingress 重點：** path-based routing 需要 rewrite-target：
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - host: app.<domain>
      http:
        paths:
          - path: /echo(/|$)(.*)
            pathType: ImplementationSpecific
```

### DNS 設定

在 Cloudflare 設定 A record（**必須用 DNS only，不能用 Proxied**）：
```
app.<domain> → <NLB-IP>
```

## Step 6: App-of-Apps Pattern

### 最終 Repo 結構

```
k8s-apps/
├── argocd/                    # Application 定義（由 app-of-apps 管理）
│   ├── app-of-apps.yaml       # 根 Application（監控 argocd/ 目錄）
│   └── echo-server.yaml       # echo-server Application
└── apps/                      # K8s manifests（被各 Application 指向）
    └── echo-server/
        ├── namespace.yaml
        ├── deployment.yaml
        ├── service.yaml
        └── ingress.yaml
```

### Apply 根 Application（唯一的手動操作）

```bash
ssh oci-cp 'bash -s' << 'REMOTE_SCRIPT'
cat > /tmp/app-of-apps.yaml << 'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:<user>/k8s-apps.git
    targetRevision: main
    path: argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
kubectl apply -f /tmp/app-of-apps.yaml
rm /tmp/app-of-apps.yaml
REMOTE_SCRIPT
```

### 新增 App 流程（之後只需要這樣）

1. `apps/<new-app>/` 放 K8s manifests
2. `argocd/<new-app>.yaml` 放 Application 定義
3. `git push` — 完成，ArgoCD 自動處理

## Troubleshooting / 踩坑記錄

### VM Public IP 過期

OCI Always Free VM 的 public IP 是 ephemeral 的，rebuild/reclaim 後會變。
```bash
cd terraform && AWS_PROFILE=oci terraform output  # 取得新 IP
# 更新 ~/.ssh/config
ssh-keygen -R <old-ip>
```

### ARM 架構 Image 不相容

`exec format error` = image 只有 amd64，但集群是 ARM。
確認 image 支援 `linux/arm64`（nginx, busybox 等官方 image 都有 multi-arch）。

### Cloudflare Proxy 擋住 Let's Encrypt

Cloudflare Proxy（橘色雲朵）會攔截 HTTP-01 challenge 請求。
必須切成 **DNS only（灰色雲朵）**，讓流量直達 NLB。

### ingress-nginx Admission Webhook 擋 ACME Challenge

ingress-nginx v1.12.0 的 admission webhook 拒絕 cert-manager 建立的 ACME challenge Ingress：
```
path /.well-known/acme-challenge/... cannot be used with pathType Exact
```

修正：
```bash
ssh oci-cp 'kubectl delete validatingwebhookconfiguration ingress-nginx-admission'
```

注意：升級 ingress-nginx 時 webhook 可能會被重建。

清除舊的 cert 資源重新簽發：
```bash
ssh oci-cp 'kubectl delete certificate <name> -n <namespace>'
# cert-manager 會根據 Ingress annotation 自動重建
```

### Path-based Routing 404

Ingress path `/echo` 不會被 rewrite，後端 nginx 收到 `/echo` 而非 `/`。
加 `rewrite-target: /$2` + regex path `/echo(/|$)(.*)` 解決。

### 手動觸發 ArgoCD 同步

不想等 3 分鐘輪詢：
```bash
ssh oci-cp 'kubectl patch app <name> -n argocd --type merge -p "{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"normal\"}}}"'
```
