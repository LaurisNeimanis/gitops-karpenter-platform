# Installation & Bootstrap Guide

This document describes the **end-to-end installation flow** for the
**GitOps Karpenter Platform**, covering both:

- **Infrastructure provisioning (Terraform)**
- **GitOps control plane and platform reconciliation (Argo CD)**

Architecture, scope, and design rationale are documented separately in  
[`README.md`](/README.md).

This guide focuses strictly on **what must be done, in what order, and where**.

---

## Installation Flow Overview

The installation consists of **two explicit phases**:

1. **Terraform (Infrastructure & Karpenter prerequisites)**
2. **GitOps (Argo CD bootstrap and platform reconciliation)**

### Terraform responsibilities

- VPC
- EKS
- Bootstrap managed node group
- Karpenter AWS-side prerequisites
- Karpenter controller installation (Helm)

Terraform installs only the Karpenter controller and AWS-side prerequisites.
All scheduling logic (NodePools, EC2NodeClasses) is managed exclusively via GitOps.

### GitOps responsibilities

- Karpenter `NodePools` and `EC2NodeClasses`
- Ingress (Traefik)
- ExternalDNS
- Workloads

These layers are **intentionally decoupled**.

---

## Prerequisites

### Local tooling

- Terraform **~> 1.14**
- AWS CLI v2
- kubectl (matching EKS version)
- Git
- (Optional) `argocd` CLI

### AWS

- AWS account with permissions for:
  - EKS, EC2, VPC, IAM, KMS, CloudWatch
  - S3 and DynamoDB (Terraform backend)

---

## 0. External Dependency — Terraform Backend (Mandatory)

This repository **does NOT create** the Terraform backend.

Before running anything here, you must bootstrap the backend using the
separate repository:

**Terraform backend bootstrap (one-time per AWS account):**  
https://github.com/LaurisNeimanis/aws-tf-backend-bootstrap

This creates:

- S3 bucket for Terraform state
- DynamoDB table for state locking

This repository **only consumes** that backend.

---

## 1. Clone the Repository

```bash
git clone https://github.com/LaurisNeimanis/gitops-karpenter-platform.git
cd gitops-karpenter-platform
```

All commands below assume execution from the repository root.

---

## 2. Terraform — Environment Bootstrap

Terraform is executed **per environment**.

### 2.1 Backend configuration (required)

Update the backend definition in:

```text
terraform/envs/dev/backend.tf
```

Set:

- S3 bucket name
- DynamoDB table name
- AWS region

The backend **must already exist**.

---

### 2.2 Environment configuration

Copy the example variables file and create the real environment configuration:

```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars
```

Then review and adjust values as required for your environment:

- AWS region
- VPC and subnet CIDRs
- Kubernetes version
- Bootstrap node instance types (must match ARM64 architecture)
- API endpoint allowlist

---

### 2.3 Apply Terraform

```bash
terraform init
terraform apply
```

This provisions:

- VPC (private subnets, S3 VPC endpoint)
- EKS cluster (API authentication mode)
- Bootstrap managed node group:
  - Amazon Linux 2023 **ARM64**
  - Example: 2× `t4g.small`
- Karpenter AWS prerequisites:
  - IAM roles
  - Instance profile
  - SQS interruption queue
  - EventBridge rules
- Karpenter controller (Helm release)

The bootstrap node group exists solely to host platform components.
Application workloads are expected to run on Karpenter-provisioned nodes.

---

## 3. Cluster Access

After a successful Terraform apply:

```bash
aws eks update-kubeconfig \
  --region eu-central-1 \
  --name eks-platform-<env>-cluster
```

Verify access:

```bash
kubectl get nodes
kubectl get pods -A
```

At this point:

- The cluster exists
- Bootstrap nodes are ready
- Karpenter controller is running
- No platform workloads are installed yet

---

## 4. GitOps — Argo CD Bootstrap

Argo CD is treated as **control-plane tooling** and is intentionally
**not managed by this GitOps repository**.

### 4.1 Install Argo CD

> **Note:**  
> Commands below assume execution from the repository root.

```bash
kubectl apply -k gitops/bootstrap/argocd
```

Verify:

```bash
kubectl get pods -n argocd
```

Wait until all pods are `Running`.

---

### 4.2 (Optional) Access Argo CD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access:

```
https://localhost:8080
```

Retrieve admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## 5. GitOps — Projects (Mandatory)

Before any applications can be registered, Argo CD Projects must exist.

```bash
kubectl apply -k gitops/argo/projects
```

This creates:

- `bootstrap`
- `platform`
- `workloads`

This step is **required**.

---

## 6. GitOps — Root Application (App-of-Apps)

Bootstrap the GitOps tree:

```bash
kubectl apply -f gitops/argo/root-application.yaml
```

From this point onward:

- Argo CD is the authoritative reconciliation engine
- Platform components are deployed automatically
- Workloads are managed via Git
- Manual `kubectl apply` should no longer be required

Any manual changes to managed resources will be reverted.

---

Domain names, DNS automation, and TLS certificate references must be reviewed and
updated separately before exposing any ingress publicly.
See [`docs/domain-configuration.md`](docs/domain-configuration.md).

---

## 7. What Gets Installed via GitOps

### Platform layer

- Karpenter configuration:
  - `EC2NodeClass` (AWS)
  - `NodePool` resources (on-demand, spot)
- Traefik ingress controller
- ExternalDNS (Cloudflare)

### Workloads

- Example workloads (e.g. `whoami`, `ccore-ai`)
- IngressRoutes
- Namespace-scoped resources only

### Workload Scheduling Profiles

Workloads are deployed using **platform-defined scheduling profiles**
(e.g. `managed-on-demand`, `karpenter-on-demand`, `karpenter-spot`).

Profiles are selected at the GitOps layer and determine:
- where workloads are scheduled
- cost and disruption characteristics

Workloads do not define node selectors or instance types in their base manifests.
Scheduling intent is applied exclusively via GitOps overlays.

---

## 8. Day-2 Operations Model

After bootstrap:

- All changes flow through Git commits
- Argo CD enforces:
  - automated sync
  - self-healing
  - deterministic ordering

Direct `kubectl` changes in managed namespaces should be avoided.

---

## What This Installation Does NOT Do

This repository does **NOT**:

- Create AWS accounts
- Create Terraform backend infrastructure
- Install observability stacks
- Manage CI/CD pipelines
- Perform application-specific autoscaling

These concerns are handled by separate repositories or layers.

---

## Environment Expansion

To add `stage` or `prod`:

1. Copy `terraform/envs/dev`
2. Adjust backend key and `terraform.tfvars`
3. Apply Terraform independently
4. Add corresponding GitOps overlays

Terraform state **must never be shared** between environments.

---

## Summary

After completing this guide:

- Infrastructure is provisioned via Terraform
- Karpenter prerequisites are in place
- Argo CD operates as the GitOps control plane
- Platform and workloads are reconciled declaratively
- Capacity is platform-owned and elastic

This installation flow is explicit, deterministic, and production-aligned.
