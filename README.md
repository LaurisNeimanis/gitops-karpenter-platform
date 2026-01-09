# GitOps Karpenter Platform — Capacity & Cost Management Layer

Production-aligned · Platform-owned · GitOps-managed · AWS-first (cloud-agnostic principles)

---

## Overview

This repository implements a **platform-owned capacity management layer** for Kubernetes clusters using **Karpenter**, managed entirely via **GitOps**.

The goal is **not** to demonstrate autoscaling mechanics, but to formalize **ownership boundaries** between the platform and application workloads:

- The **platform** owns capacity, cost, disruption, and risk
- **Workloads** express intent only (CPU / memory requirements)

This repository is designed as a **platform-level component, environment-aware by design**, and reusable across environments and clusters via GitOps overlays.

---

## What This Platform Solves

- Eliminates static node group sizing and manual capacity planning
- Centralizes cost and stability decisions at the platform level
- Prevents application teams from coupling workloads to infrastructure details
- Provides deterministic, reviewable, and auditable scaling behavior

---

## Scope & Responsibilities

### In Scope (Platform-Owned)
- Karpenter deployment and lifecycle
- NodePool and EC2NodeClass definitions
- Spot vs on-demand capacity strategy
- Consolidation and disruption policies
- Scaling guardrails and blast-radius control

### Out of Scope (Explicitly)
- AWS account bootstrap
- Terraform backend creation
- Business logic inside applications
- CI/CD pipelines

Infrastructure is treated as an **explicit external dependency**, provisioned and managed separately.

---

## Ownership Model

### Platform Responsibilities
- Define allowed capacity types and constraints
- Control pricing models and risk exposure
- Absorb node-level disruption and consolidation
- Guarantee cluster-level stability
- Own node architecture decisions (e.g. ARM64 vs x86_64)

### Workload Responsibilities
- Declare CPU and memory requirements
- Remain agnostic of node types and pricing
- Avoid infrastructure-level assumptions

> **Key principle:** workloads express intent; the platform absorbs complexity.

---

## Architecture Overview

```
[ Terraform Infrastructure ]
(VPC, EKS, IAM, bootstrap node group)
            ↓
[ GitOps Control Plane ]
(Argo CD)
            ↓
[ Karpenter Platform ]
(NodePools, scheduling profiles, disruption, consolidation)
            ↓
[ Application Workloads ]
(CPU / memory requests only, profile-selected)
```

A more detailed, lower-level architecture diagram is available in  
[`docs/architecture-diagram.mmd`](docs/architecture-diagram.mmd).

---

## Minimum Cluster Requirements (Bootstrap Capacity)

This repository assumes a **pre-existing EKS cluster** with a minimal
**bootstrap capacity** required to run platform components.

### Baseline (dev / evaluation)

- **Managed node group (bootstrap / system)**
  - AMI architecture: Amazon Linux 2023 **ARM64 (Graviton)**
  - Instance types: `t4g.small` (or other ARM-compatible types)
  - Node count: **2**
- **Purpose**
  - Run platform control-plane workloads:
    - Argo CD
    - Karpenter controller
    - Ingress (Traefik)
    - ExternalDNS
  - Provide initial scheduling capacity for platform components and
  `managed-on-demand` workloads

Single-node clusters are **not supported**.

> **Important:**  
> Bootstrap managed node groups use **ARM64 (AWS Graviton)**.  
> All instance types **must** be ARM-compatible (`t4g`, `c7g`, `m7g`, etc.).

---

### Workload Capacity (Karpenter-managed)

Application workloads are **not expected** to run on the bootstrap node group
except during initial scheduling or emergency fallback scenarios.

When workload pods are scheduled:
- Karpenter evaluates pod resource requirements
- New EC2 capacity is provisioned dynamically
- Nodes are created according to:
  - `NodePool` constraints
  - instance category and generation rules
  - spot vs on-demand strategy
  - consolidation and disruption policies

Workload capacity is therefore:
- **elastic**
- **demand-driven**
- **fully platform-controlled**

No manual node group resizing is required once Karpenter is active.

---

## Capacity Model

The platform exposes a **limited, opinionated set of capacity classes**  
via scheduling profiles, for example:

- `on-demand` — stable, predictable workloads
- `spot` — cost-optimized, disruption-tolerant workloads

Applications do **not** select instance types, pricing models, or zones.

---

## Workload Scheduling Profiles

Workloads are deployed using **explicit scheduling profiles** selected at the
GitOps layer.

Available profiles include:

- `managed-on-demand` — workloads run on the bootstrap managed node group
- `karpenter-on-demand` — workloads run on Karpenter-provisioned on-demand capacity
- `karpenter-spot` — workloads run on Karpenter-provisioned spot capacity

Profiles determine:
- whether workloads run on managed node groups or Karpenter-managed nodes
- cost characteristics and disruption tolerance

Profile selection is performed via GitOps overlays and Argo CD ApplicationSets.

Workloads do not define node selectors, instance types, or pricing models
in their base manifests.
Scheduling intent is applied exclusively via GitOps overlays.

Scheduling profiles are enforced and validated at the platform level.
Invalid or unsupported profiles will not be reconciled.

### Profile Enforcement

| Profile               | Enforcement mechanism |
|-----------------------|-----------------------|
| managed-on-demand     | Node affinity to EKS managed node group |
| karpenter-on-demand   | nodeSelector → Karpenter NodePool |
| karpenter-spot        | nodeSelector → Karpenter NodePool |

---

## Disruption & Consolidation Strategy

- Controlled consolidation to reduce idle capacity
- Explicit disruption budgets to avoid cascading failures
- Predictable node replacement behavior

Disruption is treated as a **platform concern**, never an application responsibility.

---

## Platform Surface (Beyond Capacity)

In addition to Karpenter-based capacity management, this repository also includes
a **minimal platform surface** required to validate real-world platform behavior:

- Ingress controller (Traefik)
- DNS automation (ExternalDNS)
- TLS termination via AWS ACM
- Example workloads used for validation

These components exist to **exercise and validate** the capacity platform.
They are **not the primary focus** of this repository.

---

## Cloud Scope

This implementation is **AWS-first**, leveraging:
- Amazon EKS
- EC2 instance types
- Spot and on-demand capacity
- AWS-native interruption signals

The **architectural principles** are cloud-agnostic:
- Platform-owned capacity decisions
- Workload intent abstraction
- GitOps-managed behavior

Other environments differ in provisioning mechanics, not intent.

---

## Repository Structure

```
gitops-karpenter-platform/
├── README.md
├── docs/
├── terraform/
│   └── envs/
│       └── dev/
└── gitops/
    ├── bootstrap/
    ├── argo/
    └── apps/
        ├── platform/
        └── workloads/
```

Domain names, DNS automation, and TLS termination details are documented separately in
[`docs/domain-configuration.md`](docs/domain-configuration.md).

---

## Design Principles

- Platform behavior is explicit and reviewable
- Defaults are opinionated and boring
- Safety and predictability over raw efficiency
- No hidden coupling between workloads and infrastructure
- All platform components use explicit version pinning for reproducibility

---

## Non-Goals

- Per-application tuning
- Autoscaling optimization at the workload layer
- Feature completeness
- Cloud abstraction for its own sake
- Horizontal Pod Autoscaling (HPA)

---

## Related Repositories

- AWS EKS Infrastructure Foundation (Terraform):
  https://github.com/LaurisNeimanis/aws-eks-platform

- AWS EKS GitOps Layer:
  https://github.com/LaurisNeimanis/aws-eks-gitops

- Observability Stack (GitOps-managed):
  https://github.com/LaurisNeimanis/gitops-observability-stack

---

## Status

This repository is intentionally minimal and opinionated.

It exists to demonstrate **platform-level ownership of capacity**
while remaining grounded in **real, production-aligned implementation details**.
