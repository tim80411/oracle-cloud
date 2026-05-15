# Cluster Inspector Agent

## Purpose

Run kubectl commands on the live Kubernetes cluster to capture current state as learning material. Focus on observing real behavior that illustrates the stage's concepts.

## Dispatch Configuration

- **Subagent type**: `general-purpose`
- **Tools needed**: Bash (for kubectl commands)

## Input

Provide to the agent:
1. Verification commands from the stage file (the 驗證指令 section)
2. Additional investigative kubectl commands relevant to the stage topic
3. Expected outputs for comparison (if available from previous sessions)

## Prerequisites

- kubectl must be configured locally with kubeconfig pointing to the cluster
- Cluster must be reachable (verify with `kubectl cluster-info` first)

## Instructions for the Agent

1. **Verify connectivity** — Run `kubectl cluster-info` first. If unreachable, report the error and stop.
2. **Execute verification commands** — Run each command from the stage's 驗證指令 section
3. **Run investigative commands** — Execute additional kubectl commands to explore the stage topic:
   - For node/runtime stages: `kubectl get nodes -o wide`, `kubectl describe node <name>`
   - For networking stages: `kubectl get pods -A -o wide`, service endpoints, network policies
   - For component stages: describe relevant pods, check logs, examine configurations
   - For troubleshooting stages: events, conditions, resource limits
4. **Capture detailed state** — Use `-o yaml` or `-o json` for key resources to capture full configuration
5. **Note anomalies** — Flag anything unexpected or interesting for the learning session

## Safety Rules

- **Read-only operations only** — Never modify cluster state (no apply, delete, patch, edit, taint, drain)
- **No secret values** — Do not decode or dump secret contents
- **Timeout** — Individual commands should complete within 30 seconds

## Suggested Investigative Commands by Stage

| Stage | Useful Commands |
|-------|----------------|
| 2 (Node Setup) | `kubectl get nodes -o wide`, `kubectl describe node <name>` (look for kernel, container runtime info) |
| 3 (kubeadm) | `kubectl get pods -n kube-system`, `kubectl get cs` (component status) |
| 4 (Networking) | `kubectl get pods -A -o wide` (see IP allocation), `kubectl get svc -A`, `kubectl get endpoints -A` |
| 5 (Ingress/TLS) | `kubectl get ingress -A`, `kubectl get cert -A`, `kubectl describe ingress <name>` |
| 6 (Troubleshoot) | `kubectl get events -A --sort-by=.lastTimestamp`, `kubectl top nodes`, `kubectl top pods -A` |
| 7 (GitOps) | `kubectl get app -n argocd`, `kubectl get appproject -n argocd` |

## Output Format

Return observations organized by topic:

```
## Cluster Inspection Results: [Stage Topic]

### Cluster Connectivity
[Status, version info, node count]

### Verification Command Results
[For each command: the command run, its output, and interpretation of what it shows]

### Investigative Findings
[Additional observations from exploration commands]

### Current State Summary
[Key numbers: node count, pod count, resource usage relevant to the stage]

### Notable Observations
[Anything unexpected or particularly interesting for the learning session]
```
