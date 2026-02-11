# Layer 3 GitOps 設定操作記錄（流水帳）

> 原始操作記錄，保留踩坑過程和實際指令輸出。整理版見 `layer3-setup-log.md`。

## Step 1: 建立 k8s-apps private repo

```bash
# 建立 private repo
gh repo create k8s-apps --private --description "Private Kubernetes application manifests for ArgoCD GitOps" --clone
```

clone 到了 `oracle-cloud/` 裡面（不理想，因為會變成 repo 套 repo），手動移出來：
```bash
mv oracle-cloud/k8s-apps /Users/tim80411/self/k8s-apps
```

建立基本結構：
```bash
cd /Users/tim80411/self/k8s-apps
mkdir -p apps/
# 加了 README.md 和 apps/.gitkeep
git add -A && git commit -m "Initial repo structure" && git push -u origin main
```

結果：https://github.com/tim80411/k8s-apps (private)

結構：
```
k8s-apps/
├── README.md
└── apps/
    └── .gitkeep
```

---

## Step 1.5: 更新 SSH config（IP 已過期）

嘗試 SSH 進控制平面時 timeout：
```bash
ssh -o ConnectTimeout=10 oci-cp 'echo ok'
# ssh: connect to host <OLD_CP_IP> port 22: Operation timed out
```

發現 VM public IP 已經變了（可能是 idle reclaim 或 rebuild），用 terraform output 拿到新 IP：
```bash
cd terraform && AWS_PROFILE=oci terraform output
# control_plane_public_ip = "<CP_PUBLIC_IP>"   (舊: <OLD_CP_IP>)
# worker_public_ips = ["<WORKER1_PUBLIC_IP>", "<WORKER2_PUBLIC_IP>"]
#   (舊: <OLD_WORKER1_IP>, <OLD_WORKER2_IP>)
```

更新 `~/.ssh/config` 中 oci-cp, oci-worker-1, oci-worker-2 的 HostName。
清除舊 host key：
```bash
ssh-keygen -R <OLD_CP_IP>
ssh-keygen -R <OLD_WORKER1_IP>
ssh-keygen -R <OLD_WORKER2_IP>
# 都顯示 not found in known_hosts（可能之前已清過）
```

測試新連線：
```bash
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new oci-cp 'echo "SSH OK - $(hostname)"'
# SSH OK - cp
```

教訓：OCI Always Free VM 的 public IP 是 ephemeral 的，rebuild 後會變。

---

## Step 2: 產生 SSH deploy key

```bash
ssh oci-cp 'ssh-keygen -t ed25519 -C "argocd-deploy-key" -f ~/.ssh/argocd-deploy-key -N ""'
# Generating public/private ed25519 key pair.
# Your identification has been saved in /home/ubuntu/.ssh/argocd-deploy-key
# SHA256:F0UcIJSkiWF7QOubC73JhKNn6vc/Ul06+DZOwL2sSpo argocd-deploy-key

ssh oci-cp 'cat ~/.ssh/argocd-deploy-key.pub'
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOeT9l+8gWFpwyV3ow3X43V9XoaDagbnKPDU+uG1T6DH argocd-deploy-key
```

key 存放位置：`/home/ubuntu/.ssh/argocd-deploy-key`（控制平面上）

---

## Step 3: 加到 GitHub Deploy Keys

```bash
gh repo deploy-key add - --repo tim80411/k8s-apps --title "argocd-deploy-key" <<< "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOeT9l+8gWFpwyV3ow3X43V9XoaDagbnKPDU+uG1T6DH argocd-deploy-key"

# 驗證
gh repo deploy-key list --repo tim80411/k8s-apps
# 142687196  argocd-deploy-key  read-only  ssh-ed25519 ...  2026-02-11T09:18:49Z
```

---

## Step 4: ArgoCD 註冊 private repo

### 第一次嘗試（失敗）

用 nested SSH + heredoc 方式建 Secret，`sshPrivateKey` 內容是空的：
```bash
ssh oci-cp 'kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
...
  sshPrivateKey: |
$(cat <(ssh oci-cp "cat ~/.ssh/argocd-deploy-key") | sed "s/^/    /")
EOF'
# 輸出：ssh: Could not resolve hostname oci-cp: Temporary failure in name resolution
# secret/k8s-apps-repo created（但 key 是空的）
```

驗證發現 key 空的：
```bash
ssh oci-cp 'kubectl get secret k8s-apps-repo -n argocd -o jsonpath="{.data.sshPrivateKey}" | base64 -d | head -1'
# （空）
```

原因：`$(cat <(ssh oci-cp ...))` 在本地端展開時，裡面的 `ssh oci-cp` 嘗試從遠端主機解析 `oci-cp` hostname，當然找不到。

### 第二次嘗試（成功）

刪除錯誤的 secret，改用 `ssh oci-cp 'bash -s'` 把整段 script 送到遠端執行：
```bash
ssh oci-cp 'kubectl delete secret k8s-apps-repo -n argocd'

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
  url: git@github.com:tim80411/k8s-apps.git
  sshPrivateKey: |
$(sed 's/^/    /' ~/.ssh/argocd-deploy-key)
YAML
kubectl apply -f /tmp/argocd-repo-secret.yaml
rm /tmp/argocd-repo-secret.yaml
REMOTE_SCRIPT
# secret/k8s-apps-repo created
```

驗證：
```bash
ssh oci-cp 'kubectl get secret k8s-apps-repo -n argocd -o jsonpath="{.data.sshPrivateKey}" | base64 -d | head -1'
# -----BEGIN OPENSSH PRIVATE KEY-----

ssh oci-cp 'kubectl get secret k8s-apps-repo -n argocd -o jsonpath="{.data.url}" | base64 -d'
# git@github.com:tim80411/k8s-apps.git

# GitHub SSH host key 已在 ArgoCD known hosts 中（ArgoCD 預設包含）
ssh oci-cp 'kubectl get configmap argocd-ssh-known-hosts-cm -n argocd -o jsonpath="{.data.ssh_known_hosts}" | grep github.com | head -1'
# [ssh.github.com]:443 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdH...
```

---

## Step 5: 測試 app 驗證 GitOps

### 5a. 建立 echo-server 測試應用

在 k8s-apps repo 建立 `apps/echo-server/` 目錄，包含：
- `namespace.yaml` — echo-server namespace
- `deployment.yaml` — 最初用 hashicorp/http-echo:0.2.3
- `service.yaml` — ClusterIP on port 80
- `application.yaml` — ArgoCD Application（automated sync + prune + selfHeal + CreateNamespace）

git push 後手動 apply Application。

### 5b. 手動 apply ArgoCD Application

因為還沒有 App-of-Apps，需要手動把 Application 建到集群上：
```bash
ssh oci-cp 'bash -s' << 'REMOTE_SCRIPT'
cat > /tmp/echo-server-app.yaml << 'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: echo-server
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:tim80411/k8s-apps.git
    targetRevision: main
    path: apps/echo-server
  destination:
    server: https://kubernetes.default.svc
    namespace: echo-server
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML
kubectl apply -f /tmp/echo-server-app.yaml
rm /tmp/echo-server-app.yaml
REMOTE_SCRIPT
# application.argoproj.io/echo-server created
```

等 10 秒後查看狀態：
```bash
ssh oci-cp 'kubectl get app echo-server -n argocd -o jsonpath="{.status.sync.status} / {.status.health.status}"'
# Synced / Progressing
```

### 5c. 踩坑：ARM 架構 image 不相容

等 pod ready 後發現 CrashLoopBackOff：
```bash
ssh oci-cp 'kubectl get pods -n echo-server'
# echo-server-546bcc7b8c-2dg7m   0/1   CrashLoopBackOff   4 (84s ago)   3m6s

ssh oci-cp 'kubectl logs -n echo-server deployment/echo-server --tail=20'
# exec /http-echo: exec format error
```

原因：`hashicorp/http-echo:0.2.3` 只有 amd64，但集群是 ARM (A1.Flex)。
修正：改用 `nginx:alpine`（multi-arch，支援 arm64）。同時改 service targetPort 從 5678 到 80。

push 修正後，用 annotation 觸發 ArgoCD 立即刷新（不用等 3 分鐘輪詢）：
```bash
ssh oci-cp 'kubectl patch app echo-server -n argocd --type merge -p "{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"normal\"}}}"'
```

### 5d. 驗證 GitOps 循環

```bash
ssh oci-cp 'kubectl get pods -n echo-server'
# echo-server-6cd5b77bc7-5nlb9   1/1   Running   0   30s

ssh oci-cp 'kubectl get app echo-server -n argocd -o jsonpath="Sync: {.status.sync.status} / Health: {.status.health.status}"'
# Sync: Synced / Health: Healthy

ssh oci-cp 'curl -s -o /dev/null -w "%{http_code}" http://10.96.151.3'
# 200
```

GitOps 循環驗證通過！push 到 GitHub → ArgoCD 自動同步 → Pod 部署成功。

### 5e. Ingress + TLS 設定

在 `apps/echo-server/ingress.yaml` 加入 Ingress：
- Host: `<YOUR_DOMAIN>`，path-based routing `/echo`
- TLS: cert-manager + letsencrypt-prod ClusterIssuer

push 後 ArgoCD 自動同步：
```bash
ssh oci-cp 'kubectl get ingress -n echo-server'
# NAME          CLASS   HOSTS                     ADDRESS    PORTS     AGE
# echo-server   nginx   <YOUR_DOMAIN>   10.0.0.3   80, 443   7m26s
```

### 5f. 踩坑：Cloudflare Proxy 模式

```bash
dig +short <YOUR_DOMAIN>
# 172.67.200.23
# 104.21.21.201
```

DNS 解析到 Cloudflare proxy IP，不是 NLB IP `<NLB_PUBLIC_IP>`。
原因：Cloudflare 預設開了 Proxy（橘色雲朵）。
修正：切換成 **DNS only（灰色雲朵）**。

切換後本地 DNS 快取還沒更新，但透過 Cloudflare DNS 確認已生效：
```bash
dig <YOUR_DOMAIN> @1.1.1.1 +short
# <NLB_PUBLIC_IP>
```

### 5g. 踩坑：ingress-nginx admission webhook 擋 ACME challenge

cert-manager 的 Certificate 一直是 READY: False：
```bash
ssh oci-cp 'kubectl get certificate -n echo-server'
# NAME      READY   SECRET    AGE
# app-tls   False   app-tls   13m
```

追查原因：
```bash
ssh oci-cp 'kubectl describe challenge -n echo-server | tail -20'
# Reason: admission webhook "validate.nginx.ingress.kubernetes.io" denied the request:
#   ingress contains invalid paths: path /.well-known/acme-challenge/... cannot be used with pathType Exact
# State: pending
```

ingress-nginx v1.12.0 的 admission webhook 拒絕 cert-manager 建立的 ACME challenge Ingress。

修正：刪除 webhook（它只做 Ingress 語法預檢查，非必需）：
```bash
ssh oci-cp 'kubectl delete validatingwebhookconfiguration ingress-nginx-admission'
```

清除舊的 cert 資源讓 cert-manager 重試：
```bash
ssh oci-cp 'kubectl delete challenge --all -n echo-server'
ssh oci-cp 'kubectl delete order --all -n echo-server'
ssh oci-cp 'kubectl delete certificaterequest --all -n echo-server'
ssh oci-cp 'kubectl delete certificate app-tls -n echo-server'
# Ingress 上的 annotation 會觸發 cert-manager 自動重建 Certificate
```

等 20 秒後：
```bash
ssh oci-cp 'kubectl get certificate -n echo-server'
# NAME      READY   SECRET    AGE
# app-tls   True    app-tls   49s
```

### 5h. 踩坑：path-based routing 需要 rewrite-target

TLS 通了但存取 `/echo` 回 404：
```bash
curl --resolve <YOUR_DOMAIN>:443:<NLB_PUBLIC_IP> -s -o /dev/null -w "HTTP %{http_code} / TLS %{ssl_verify_result}" https://<YOUR_DOMAIN>/echo
# HTTP 404 / TLS 0
```

TLS 合法（ssl_verify_result: 0），但 404 是因為 nginx pod 收到的路徑是 `/echo`，而 nginx 預設只有 `/` 的歡迎頁。

修正：加 rewrite-target annotation：
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - host: <YOUR_DOMAIN>
      http:
        paths:
          - path: /echo(/|$)(.*)
            pathType: ImplementationSpecific
```

push 後觸發 refresh，最終驗證：
```bash
curl --resolve <YOUR_DOMAIN>:443:<NLB_PUBLIC_IP> -s https://<YOUR_DOMAIN>/echo | head -5
# <!DOCTYPE html>
# <html>
# <head>
# <title>Welcome to nginx!</title>
# <style>
```

---

## Step 6: App-of-Apps pattern

### 6a. 重整目錄結構

把 `apps/echo-server/application.yaml` 搬到 `argocd/echo-server.yaml`：
```bash
mkdir -p argocd/
mv apps/echo-server/application.yaml argocd/echo-server.yaml
```

建立根 Application `argocd/app-of-apps.yaml`（監控 `argocd/` 目錄）。

重點：Application 定義不能放在被它自己管理的 `apps/echo-server/` 裡面，否則會造成「Application 管理自己」的循環。

### 6b. 刪除手動 Application，讓 app-of-apps 接管

```bash
# 用 --cascade=orphan 只刪 Application 物件，保留 echo-server 的 pods/services
ssh oci-cp 'kubectl delete app echo-server -n argocd --cascade=orphan'
# application.argoproj.io "echo-server" deleted

# apply 根 Application（省略完整 YAML，見整理版）
ssh oci-cp 'kubectl apply -f /tmp/app-of-apps.yaml'
# application.argoproj.io/app-of-apps created
```

### 6c. 驗證

```bash
ssh oci-cp 'kubectl get app -n argocd'
# NAME          SYNC STATUS   HEALTH STATUS
# app-of-apps   Synced        Healthy
# echo-server   Synced        Healthy

ssh oci-cp 'kubectl get pods -n echo-server'
# echo-server-6cd5b77bc7-5nlb9   1/1   Running   0   41m
```

app-of-apps 自動從 `argocd/` 目錄讀取 `echo-server.yaml` 並建立了 echo-server Application。
Pod 全程沒有中斷（感謝 `--cascade=orphan`）。

之後新增 app 只需要：
1. 在 `apps/<new-app>/` 放 K8s manifests
2. 在 `argocd/<new-app>.yaml` 放 Application 定義
3. git push — app-of-apps 會自動建立新 Application，新 Application 再自動同步 manifests
