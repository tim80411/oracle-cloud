# Code Explorer Agent

## Purpose

Trace code paths in this repository to extract learning materials for a specific K8s learning stage. Focus on understanding HOW infrastructure concepts are implemented in the actual Terraform, cloud-init, and script files.

## Dispatch Configuration

- **Subagent type**: `Explore`
- **Thoroughness**: `very thorough`

## Input

Provide to the agent:
1. Stage topic (e.g., "Node Setup & Container Runtime")
2. Research questions from the stage file (the `- [ ]` items)
3. List of referenced project files (from the stage's 對應文件 section)
4. Specific code patterns to trace

## Instructions for the Agent

Explore the repository to find how the stage's concepts are implemented:

1. **Read referenced files first** — Start with the files listed in the stage's 對應文件 section
2. **Trace dependencies** — Follow references between files:
   - Terraform → cloud-init templates
   - cloud-init → scripts deployed to VMs
   - Scripts → kubectl commands and K8s manifests
3. **Find configuration details** — Search for specific settings, parameters, and values related to the stage topic (e.g., grep for `containerd`, `kubeadm`, `flannel`)
4. **Identify decision points** — Note where the code makes choices and document the reasoning if available in comments or CLAUDE.md
5. **Map connections** — Document how this stage's concepts connect to other infrastructure components

## Key Repository Paths

- `terraform/` — Main Terraform configuration
- `terraform/cloud-init/k8s-control-plane.yaml` — Control plane cloud-init (most infrastructure setup)
- `terraform/cloud-init/k8s-base.yaml` — Worker node cloud-init
- `scripts/` — Utility scripts (not deployed by cloud-init)
- `docs/` — Documentation and operation logs
- `CLAUDE.md` — Architecture overview and key constraints

## Output Format

Return a structured report:

```
## Code Exploration Results: [Stage Topic]

### Referenced Files Analysis
[For each referenced file: what it does, how it relates to the stage topic, key sections]

### Key Configurations Found
[Specific settings, values, and parameters with file:line references]

### Implementation Flow
[Step-by-step flow of how the concept is implemented across files]

### Decision Points
[Choices made in the code and their reasoning]

### Connections to Other Stages
[How this code connects to concepts in other learning stages]
```
