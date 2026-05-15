---
name: k8s-learning
description: This skill should be used when the user wants to "繼續階段" (continue a stage), "開始學習" (start learning), "start stage N", "continue learning session", "begin learning", "resume K8s learning", "review stage N", or asks "下一個階段是什麼" (what is the next stage). Also trigger when the user asks about K8s learning stages or progress, or wants to learn Kubernetes concepts through this project's infrastructure.
---

# K8s Learning Session Methodology

Orchestrate structured learning sessions for Kubernetes concepts through this project's Always Free OCI infrastructure. Each session covers one learning stage, progressing from architecture overview to GitOps mastery through a 5-phase process.

## Session Initialization

### Determine Target Stage

1. Check which stage the user wants. Accept phrases like "繼續階段 N", "start stage N", or "下一個階段".
2. Read the stage file from `.claude-plugin/references/stage-N-*.md` to understand:
   - Research questions (unchecked `- [ ]` items need investigation)
   - Referenced project documents (the 對應文件 section)
   - Verification commands and break experiment designs
3. Identify the stage's completion status:
   - ✅ = completed — offer review or recall check
   - ⬜ = not started — begin from Phase 1
   - Partially filled = resume from the appropriate phase
4. **Activate session logging**: Run `echo "stage-N" > .k8s-learning-session` (replace N with the stage number). This enables the Stop hook to auto-organize the learning log after each exchange.

### Stage Progression

Completion status is tracked in each stage file's header (✅ or ⬜). Read the target stage file to check current status.

| Stage | Topic |
|-------|-------|
| 1 | Architecture Overview |
| 2 | Node Setup & Container Runtime |
| 3 | Cluster Creation (kubeadm) |
| 4 | K8s Networking |
| 5 | Ingress & TLS |
| 6 | Troubleshooting |
| 7 | GitOps (ArgoCD) |

## Phase 1: Research (Parallel Agent Dispatch)

Dispatch three research agents **in parallel** using the Task tool. Each agent operates independently to gather material for the current stage.

### Dispatch Procedure

Read each agent definition file, then dispatch all three simultaneously in a single message with multiple Task tool calls:

1. **Code Explorer** — Read `.claude-plugin/agents/code-explorer.md` for full instructions.
   - Dispatch with `subagent_type: Explore`, thoroughness: `very thorough`
   - Provide: stage topic, research questions, referenced project files

2. **Web Researcher** — Read `.claude-plugin/agents/web-researcher.md` for full instructions.
   - Dispatch with `subagent_type: general-purpose`
   - Provide: research questions, key concepts, component versions from CLAUDE.md

3. **Cluster Inspector** — Read `.claude-plugin/agents/cluster-inspector.md` for full instructions.
   - Dispatch with `subagent_type: general-purpose`
   - Provide: verification commands from the stage, additional investigative commands

### Handling Results

Collect all three agent results before proceeding. If an agent fails (e.g., cluster unreachable for inspector), note the gap and proceed with available material. Present a brief summary of findings to the user.

## Phase 2: Compile

Integrate agent outputs into the stage reference file.

1. Return to the stage file (`.claude-plugin/references/stage-N-*.md`) read during initialization
2. Update each section with agent findings:
   - **研究問題**: Mark answered questions `- [x]`, add concise findings
   - **使用情境**: Enrich with code explorer details (real implementation specifics)
   - **情境延伸**: Add alternatives/comparisons from web researcher
   - **驗證指令**: Update with actual cluster inspector output
   - **破壞實驗**: Refine expected behaviors based on findings
3. Present a compiled summary to the user before proceeding

## Phase 3: Learn & Practice

Guide interactive learning through the compiled materials.

1. Walk through stage concepts in order, connecting theory to this project's implementation
2. For each concept:
   - Explain what it does and why it matters in this specific infrastructure
   - Show where it appears in the project (reference specific files and configs)
   - Run verification commands on the cluster, interpret results together
3. Encourage the user to run commands and observe outputs themselves
4. Answer questions as they arise, connecting answers to other stages when relevant
5. Track understanding gaps for Phase 4 destruction experiments

## Phase 4: Break & Fix

Design and guide intentional destruction experiments.

1. Read the stage's **破壞實驗** section for pre-designed experiments
2. For each experiment:
   - Explain what will be broken and expected symptoms
   - Guide the user to execute the break command
   - **Do NOT provide the fix immediately** — let the user attempt diagnosis
   - Offer progressive hints if stuck: symptom → component → specific fix
   - After resolution, explain the root cause chain
3. If no pre-designed experiments exist, design one based on Phase 3 findings:
   - Target a concept the user found challenging
   - Choose a reversible operation
   - Document the experiment in the stage file

## Phase 5: Wrap-up

Consolidate learning and prepare for future recall.

1. **Recall Check**: Present the stage's recall questions one at a time
   - Let the user answer before revealing the expected answer
   - Add new recall questions based on Phase 3-4 discoveries
2. **Concept Connections**: Review the **概念連結** section
   - Highlight connections to previously completed stages
   - Preview connections to upcoming stages
3. **Production Comparison**: Discuss **生產環境對照**
   - How would this concept differ in a production environment?
   - What trade-offs exist between learning setup and production?
4. **Learning Notes**: Help the user write a brief session summary in **學習筆記**
5. **Mark Complete**: Change ⬜ to ✅ in the stage file header
6. **Deactivate session logging**: Run `rm -f .k8s-learning-session .k8s-learning-logged` to stop the auto-logging hook

## Agent Index

Agent definitions for Phase 1 dispatch (read before dispatching):

| Agent | File | Dispatch Type | Purpose |
|-------|------|---------------|---------|
| Code Explorer | `.claude-plugin/agents/code-explorer.md` | `Explore` | Trace project code paths |
| Web Researcher | `.claude-plugin/agents/web-researcher.md` | `general-purpose` | Search official docs & community |
| Cluster Inspector | `.claude-plugin/agents/cluster-inspector.md` | `general-purpose` | Observe live cluster state |

## Stage Reference Index

Learning stages in `.claude-plugin/references/`:

| Stage | File | Key Concepts |
|-------|------|--------------|
| 1 | `.claude-plugin/references/stage-1-architecture.md` | Three-layer architecture, K8s components, traffic path |
| 2 | `.claude-plugin/references/stage-2-node-setup.md` | Kernel modules, containerd, CRI, cgroup |
| 3 | `.claude-plugin/references/stage-3-kubeadm.md` | kubeadm init/join, Bootstrap Token, etcd, Taint |
| 4 | `.claude-plugin/references/stage-4-networking.md` | Flannel CNI, kube-proxy, CoreDNS, three-layer networking |
| 5 | `.claude-plugin/references/stage-5-ingress-tls.md` | ingress-nginx, cert-manager, ACME, NLB integration |
| 6 | `.claude-plugin/references/stage-6-troubleshooting.md` | iptables debugging, NLB health check, systematic diagnosis |
| 7 | `.claude-plugin/references/stage-7-gitops.md` | ArgoCD, App-of-Apps, Sealed Secrets, sync policy |

## Concept Connection Map

```
Stage 1 Architecture ─────────────────────────────────┐
  │                                                     │
  ▼                                                     │
Stage 2 Node Setup ──→ Stage 3 kubeadm ──→ Stage 4 Net │
  │ (kernel modules)    │ (init/join)    │ (CNI/Svc)    │
  │                     │                │              │
  │    br_netfilter ────┘────────────────┘              │
  │                                                     │
  └───────────────→ Stage 5 Ingress & TLS               │
                        │ (L7 + TLS)                    │
                        ▼                               │
                    Stage 6 Troubleshooting ←───────────┘
                        │ (iptables + NLB + full arch)
                        ▼
                    Stage 7 GitOps
                      (ArgoCD + app delivery)
```
