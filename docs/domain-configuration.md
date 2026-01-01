# Domain & TLS Configuration Guide

This repository contains **example domain names and TLS certificate references**
owned by the author.

Before deploying this platform in another environment, **all domain- and
certificate-related values must be updated**.

This document describes **what must be changed, where, and why**.

---

## Scope of This Document

Domain and TLS configuration in this repository affects:

- ExternalDNS behavior
- Ingress exposure
- TLS termination at the AWS Network Load Balancer
- Public accessibility of workloads

This repository **does NOT**:
- create DNS zones
- issue TLS certificates
- validate DNS ownership
- manage certificate lifecycle

All DNS zone management and ACM certificate lifecycle are handled outside this
repository by the Terraform infrastructure layer.

---

## Ownership Model (Important)

**Infrastructure layer (`aws-eks-platform`)**
- Owns ACM certificates
- Owns DNS validation for certificate issuance (Cloudflare)
- Owns certificate lifecycle

**This repository (`gitops-karpenter-platform`)**
- References an existing ACM certificate
- Declares ingress hostnames
- Relies on ExternalDNS for record management

No certificate or DNS resources are created here.

---

## Infrastructure Dependencies (Authoritative Source)

All DNS zones, TLS certificates, and provider credentials required by this
repository are provisioned by the **Terraform infrastructure repository**:

**AWS EKS Infrastructure (Terraform)**  
https://github.com/LaurisNeimanis/aws-eks-platform

That repository is the authoritative source for DNS zones, ACM certificates,
and Cloudflare credentials required by this platform.

This repository assumes those resources already exist and only
**references them declaratively**.

---

## Cloudflare API Token (Consumed by GitOps)

ExternalDNS requires a Cloudflare API token.

This repository only expects the token to be exposed as a Kubernetes Secret:

- **Name:** `cloudflare-api-token`
- **Namespace:** `external-dns`
- **Key:** `CF_API_TOKEN`

No Cloudflare credentials are created or rotated here.

---

## Required Changes Before Deployment

### 1. ExternalDNS domain filters

ExternalDNS is configured to manage DNS records **only for specific domains**
and **only for Kubernetes Services** exposed by the platform.

**File**  
`gitops/apps/platform/external-dns/values/values.yaml`

**Current value**
```yaml
domainFilters:
  - ccore.ai
```

**Action**

Replace `ccore.ai` with a domain you own and manage.

**Example**
```yaml
domainFilters:
  - example.com
```

If this value is not updated:
- ExternalDNS will ignore your domains
- No DNS records will be created

---

### 2. Ingress hostname (shared entrypoint)

The platform uses a single shared ingress endpoint exposed via Traefik.

**File**  
`gitops/apps/platform/traefik/values/values.yaml`

**Current value**
```yaml
external-dns.alpha.kubernetes.io/hostname: ingress.ccore.ai
```

**Action**

Update to the ingress hostname used in your environment.

**Example**
```yaml
external-dns.alpha.kubernetes.io/hostname: ingress.example.com
```

This hostname represents:
- the public entrypoint of the cluster
- the target for all application CNAME records

---

### 3. Workload ingress hostnames

Each workload defines its own public hostname via Traefik `IngressRoute` resources.

#### whoami example

**File**  
`gitops/apps/workloads/whoami/base/ingressroute-https.yaml`

**Current value**
```yaml
match: Host(`whoami.ccore.ai`)
```

**Replace with**
```yaml
match: Host(`whoami.example.com`)
```

#### ccore-ai example

**File**  
`gitops/apps/workloads/ccore-ai/base/ingressroute-https.yaml`

**Current value**
```yaml
match: Host(`demo.ccore.ai`)
```

**Replace with**
```yaml
match: Host(`demo.example.com`)
```

Workload hostnames must:
- belong to a domain covered by ExternalDNS filters
- resolve (via CNAME or alias) to the shared ingress hostname
- NOT be managed directly by ExternalDNS

---

### 4. AWS ACM certificate (mandatory)

TLS is terminated at the AWS Network Load Balancer, not inside Traefik.
This is why the ACM certificate ARN is referenced at the Service level.

Traefik operates behind the load balancer and does not manage certificates.

#### Certificate reference

**File**  
`gitops/apps/platform/traefik/values/values.yaml`

**Current value**
```yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:eu-central-1:277679348320:certificate/18a3f75f-1fb2-461d-9aa2-c3b60591d773"
```

**Action**

Replace this ARN with your own ACM certificate ARN.

**Example**
```yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:eu-central-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

#### Certificate requirements

The ACM certificate must:
- exist in the same AWS account as the EKS cluster
- exist in the same AWS region
- cover the ingress hostname (e.g. `ingress.example.com`)
- ideally include wildcard coverage (e.g. `*.example.com`)

The ACM certificate must be provisioned by the Terraform infrastructure
repository and is not created by this GitOps layer.

If the certificate ARN is:
- missing
- invalid
- from another account or region

the AWS Network Load Balancer will fail to provision and HTTPS ingress
will not function.

For certificate creation and DNS validation details, refer to the
aws-eks-platform repository documentation.

---

## DNS Flow Overview

```
Client
  ↓
DNS (Cloudflare)
  ↓
AWS NLB (TLS termination via ACM)
  ↓
Traefik Ingress Controller
  ↓
Application Workloads
```

DNS records are managed automatically by ExternalDNS.
No manual DNS changes should be required after bootstrap.

---

## What This Repository Does NOT Do

This repository does not:

- create DNS zones
- issue or validate ACM certificates
- manage Cloudflare API tokens
- configure DNS providers
- manage certificate lifecycle

---

## Summary Checklist

Before deploying this platform:

- Replace all `ccore.ai` domain references
- Ensure ExternalDNS domain filters match your domain
- Update ingress hostname
- Update workload hostnames
- Provide a valid ACM certificate ARN
- Confirm certificate exists in the correct AWS account and region
- Commit and let Argo CD reconcile all changes

Failing to update these values will result in broken ingress and DNS behavior.

This separation keeps the platform portable, predictable, and production-safe.
