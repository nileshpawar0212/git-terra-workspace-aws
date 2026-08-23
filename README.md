# Private EKS Cluster — Terraform on AWS

## Project Overview

This project provisions a **fully private Amazon EKS cluster** on AWS using Terraform.
Infrastructure is modular, multi-environment, and managed via **Terraform Cloud (HCP Terraform)**
with a **VCS-driven workflow** — pushing code to Git automatically triggers plan and apply.

---

## Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │                  AWS VPC                     │
                        │           CIDR: 10.x.0.0/16                 │
                        │                                              │
                        │  ┌─────────────────┐  ┌─────────────────┐  │
                        │  │  Public Subnet 1 │  │  Public Subnet 2│  │
                        │  │  us-east-1a      │  │  us-east-1b     │  │
                        │  │  [NAT Gateway]   │  │                 │  │
                        │  └────────┬─────────┘  └─────────────────┘  │
                        │           │  IGW ──────────────── Internet   │
                        │           │                                  │
                        │  ┌────────▼────────┐  ┌─────────────────┐  │
                        │  │ Private Subnet 1│  │ Private Subnet 2│  │
                        │  │  us-east-1a     │  │  us-east-1b     │  │
                        │  │  [EKS Nodes]    │  │  [EKS Nodes]    │  │
                        │  │  [EKS Control]  │  │  [EKS Control]  │  │
                        │  └─────────────────┘  └─────────────────┘  │
                        │                                              │
                        │  VPC Endpoints (Interface):                  │
                        │  ec2 | ecr.api | ecr.dkr | sts | logs |     │
                        │  autoscaling                                 │
                        │                                              │
                        │  VPC Endpoint (Gateway): S3                  │
                        └─────────────────────────────────────────────┘
```

---

## Project Structure

```
git-terra-workspace-aws/
├── main.tf               # Root — calls all modules, workspace config map
├── variables.tf          # aws_region variable
├── providers.tf          # AWS provider
├── versions.tf           # Terraform Cloud backend + provider versions
└── modules/
    ├── vpc/              # VPC, subnets, IGW, NAT GW, route tables, S3 endpoint
    ├── iam/              # EKS cluster role + node group IAM role
    ├── sg/               # Cluster SG + Node SG with separate rules
    ├── endpoints/        # VPC interface endpoints for private cluster
    └── eks/
        ├── cluster/      # EKS control plane + addons
        └── nodegroup/    # Launch template + node group (Bottlerocket)
```

---

## Modules Breakdown

### vpc
| Resource | Purpose |
|---|---|
| `aws_vpc` | VPC with DNS support and DNS hostnames enabled |
| `aws_subnet` x4 | 2 public + 2 private across 2 AZs |
| `aws_internet_gateway` | Internet access for public subnets |
| `aws_eip` + `aws_nat_gateway` | Zonal NAT for private subnet outbound traffic |
| `aws_route_table` x2 | Public (→ IGW) and Private (→ NAT) route tables |
| `aws_vpc_endpoint` (Gateway) | S3 gateway endpoint — free, no NAT cost for S3 |

### iam
| Resource | Policies Attached |
|---|---|
| EKS Cluster Role | `AmazonEKSClusterPolicy` |
| Node Group Role | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |

### sg
- Cluster SG and Node SG created empty first to avoid circular dependency
- Rules added separately via `aws_security_group_rule`:
  - Nodes → Cluster: port 443 (API server)
  - Cluster → Nodes: ports 1025–65535 (kubelet + pods)
  - Node → Node: all traffic (self)

### endpoints
- 6 interface endpoints deployed in private subnets with `private_dns_enabled = true`
- Required because cluster has `endpoint_public_access = false`
- Without these, nodes cannot pull images or authenticate

### eks/cluster
- `endpoint_private_access = true`, `endpoint_public_access = false` — fully private
- All control plane logs enabled (api, audit, authenticator, controllerManager, scheduler)
- Addons (vpc-cni, coredns, kube-proxy) version auto-resolved via `aws_eks_addon_version` data source based on cluster version

### eks/nodegroup
- Bottlerocket AMI auto-fetched from SSM Parameter Store based on `cluster_version`
- Custom launch template with gp3 EBS, 20GB root volume
- `update_config.max_unavailable = 1` — rolling node replacement during upgrades
- `lifecycle.ignore_changes` on `desired_size` — safe for cluster autoscaler

---

## Multi-Environment with Terraform Workspaces

All environment config is in a single `workspace_config` map in `main.tf`.
`terraform.workspace` selects the correct config automatically.

| Workspace | k8s Version | VPC CIDR | Instance | Nodes |
|---|---|---|---|---|
| `dev` | 1.32 | 10.0.0.0/16 | t3.medium | 1–3 |
| `staging` | 1.32 | 10.1.0.0/16 | t3.medium | 1–4 |
| `prod` | 1.32 | 10.2.0.0/16 | t3.large | 2–6 |

---

## Terraform Cloud — VCS Driven Workflow

```
Developer pushes code to GitHub
          │
          ▼
Terraform Cloud detects change via webhook
          │
          ▼
Auto triggers Plan
          │
          ▼
dev  → Auto Apply
staging/prod → Manual Approval required
```

### Branch to Workspace Mapping
| Branch | TFC Workspace |
|---|---|
| `dev` | dev |
| `staging` | staging |
| `main` | prod |

---

## EKS Upgrade Strategy

Change `cluster_version` in `main.tf` for the target workspace and push to Git.

```
cluster_version = "1.33"   ← change this
        │
        ▼
TFC triggers apply
        │
        ├── 1. EKS control plane upgrades
        ├── 2. Addons auto-resolve latest version for 1.33
        ├── 3. SSM resolves new Bottlerocket AMI for 1.33
        ├── 4. New launch template version created
        └── 5. Node group rolling replacement (max_unavailable=1)
```

**Safe upgrade order:**
```bash
# Step 1 — control plane first
terraform apply -target=module.eks_cluster

# Step 2 — nodes after control plane is ready
terraform apply -target=module.eks_nodegroup
```

EKS supports nodes one version behind control plane, so there is no downtime between steps.

---

## Why Bottlerocket?

| Feature | Bottlerocket | Amazon Linux 2 |
|---|---|---|
| OS footprint | Minimal, container-optimized | General purpose |
| Attack surface | Very small, read-only root FS | Larger |
| Updates | Atomic image-based updates | Package-based |
| Boot time | Faster | Slower |
| SSH access | Not available by default | Available |

---

## Prerequisites

```bash
# Install Terraform
terraform -version  # >= 1.5.0

# Login to Terraform Cloud
terraform login

# Configure AWS credentials in TFC workspace as environment variables:
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
```

## Deployment

```bash
# Create workspaces in TFC UI, then:
terraform workspace select dev
terraform init
terraform apply
```

---
---

# Interview Questions & Answers

## Terraform

**Q: What is the difference between `terraform.tfvars` and workspace config map approach you used?**

A: `tfvars` files require separate files per environment (`dev.tfvars`, `prod.tfvars`) and you must pass `-var-file` manually. The workspace config map approach keeps all environment config in one place inside `main.tf`, and `terraform.workspace` automatically selects the right config. It reduces file sprawl and makes environment differences easy to compare side by side.

---

**Q: Why did you use `aws_security_group_rule` separately instead of inline ingress/egress blocks?**

A: Inline rules inside `aws_security_group` cause a circular dependency when two security groups reference each other — Terraform cannot determine which to create first. By creating both SGs empty and attaching rules separately via `aws_security_group_rule`, Terraform creates both SGs first, then attaches the cross-referencing rules without any cycle.

---

**Q: What is `lifecycle { ignore_changes }` used for in the node group?**

A: The `desired_size` in the node group scaling config is managed by the Cluster Autoscaler at runtime. If Terraform tracks it, every `terraform apply` would reset the node count back to the value in code, overriding what the autoscaler set. `ignore_changes` tells Terraform to ignore drift on that field so autoscaler can manage it freely.

---

**Q: What is `create_before_destroy` in the launch template?**

A: When a launch template is updated (e.g. new AMI), Terraform by default destroys the old one before creating the new one. If the node group still references the old version during that window, it causes an error. `create_before_destroy` ensures the new launch template version exists before the old one is removed.

---

**Q: How does Terraform Cloud differ from running Terraform locally?**

A: With local Terraform, state is stored on your machine or in an S3 backend, runs happen on your machine, and credentials are local env vars. Terraform Cloud stores state remotely with locking, runs plan/apply on managed runners, stores credentials securely as workspace variables, provides run history, audit logs, and team-based access control. The VCS integration also means infrastructure changes go through the same Git review process as application code.

---

**Q: What happens if you run `terraform apply` on the wrong workspace?**

A: Each workspace has its own isolated state file in Terraform Cloud. Applying on the wrong workspace would attempt to create/modify infrastructure for that environment. The workspace config map would use the wrong CIDR, cluster name, and sizing. This is why branch-to-workspace mapping is important — `dev` branch only triggers the `dev` workspace in TFC.

---

**Q: What is a Terraform data source and where did you use it?**

A: A data source reads existing information from a provider without creating anything. Used in three places:
- `aws_ssm_parameter` — reads the latest Bottlerocket AMI ID from AWS SSM for the given k8s version
- `aws_eks_addon_version` — reads the latest compatible addon version for the cluster version
- `aws_region` — reads the current AWS region to build endpoint service names dynamically

---

## EKS & Kubernetes

**Q: Why is the EKS cluster fully private? What are the trade-offs?**

A: A private cluster means the Kubernetes API server endpoint is only accessible from within the VPC. This eliminates exposure of the API server to the internet, reducing the attack surface significantly. The trade-off is that `kubectl` commands must be run from within the VPC (bastion host, VPN, or AWS Cloud9). It also requires VPC endpoints so nodes can reach AWS services without going through the internet.

---

**Q: Why do you need VPC endpoints for a private EKS cluster?**

A: With `endpoint_public_access = false`, nodes have no path to the internet. But they still need to reach AWS APIs to:
- Pull container images from ECR (`ecr.api`, `ecr.dkr`)
- Authenticate with IAM (`sts`)
- Register with the cluster (`ec2`)
- Send logs to CloudWatch (`logs`)
- Scale node groups (`autoscaling`)

VPC interface endpoints create private ENIs inside the VPC so these API calls never leave the AWS network.

---

**Q: Why is S3 a Gateway endpoint and not an Interface endpoint?**

A: S3 Gateway endpoint is free and works by adding a route in the route table pointing S3 traffic to the endpoint. Interface endpoints cost money per hour per AZ. For S3, the Gateway type is sufficient and more cost-effective. It is attached to both public and private route tables so all subnets benefit.

---

**Q: What is the difference between EKS control plane upgrade and node group upgrade?**

A: The control plane upgrade updates the Kubernetes API server, etcd, scheduler, and controller manager managed by AWS. Node group upgrade replaces the EC2 instances running worker nodes with new instances using the updated AMI. They are independent — EKS supports nodes one minor version behind the control plane. Control plane must always be upgraded first.

---

**Q: Why did you choose Bottlerocket over Amazon Linux 2 for nodes?**

A: Bottlerocket is purpose-built for running containers. It has a minimal read-only root filesystem which reduces the attack surface. Updates are atomic — the entire OS image is replaced rather than individual packages, making rollback reliable. It boots faster than Amazon Linux 2 and has no SSH by default, which aligns with immutable infrastructure principles.

---

**Q: What is `max_unavailable = 1` in update_config?**

A: During a node group rolling update, EKS drains and terminates nodes one at a time. `max_unavailable = 1` means only one node is unavailable at any point during the upgrade. This ensures the workload continues running on the remaining nodes. For production you might set this to a percentage like `max_unavailable_percentage = 25`.

---

**Q: What are EKS addons and why do you auto-resolve their versions?**

A: EKS addons are AWS-managed components — vpc-cni handles pod networking, coredns handles DNS, kube-proxy handles network rules. Each addon has versions compatible with specific k8s versions. By using the `aws_eks_addon_version` data source with `most_recent = true`, the correct addon version is automatically selected when the cluster version changes, avoiding manual version lookups during upgrades.

---

**Q: What is `resolve_conflicts_on_update = OVERWRITE` in addons?**

A: If you have manually modified addon configuration (e.g. changed vpc-cni settings), during an addon upgrade Terraform would fail because the desired config conflicts with the existing config. `OVERWRITE` tells EKS to overwrite any manual changes with the addon defaults during update. The alternative is `PRESERVE` which keeps manual changes but may fail if there are conflicts.

---

## Networking

**Q: Why is the NAT Gateway only in one AZ (zonal)?**

A: For demo/dev purposes, a single NAT Gateway in one AZ is sufficient and cost-effective. In production you would deploy one NAT Gateway per AZ with separate private route tables per AZ. This avoids cross-AZ data transfer costs and provides high availability — if one AZ goes down, the other AZ's nodes still have outbound internet access through their own NAT Gateway.

---

**Q: Why are EKS nodes placed in private subnets?**

A: Worker nodes should never be directly accessible from the internet. Placing them in private subnets means they have no public IPs and inbound traffic can only come from within the VPC. Outbound traffic goes through the NAT Gateway. This follows the principle of least exposure.

---

**Q: What is `enable_dns_hostnames` and `enable_dns_support` on the VPC?**

A: `enable_dns_support` enables the Route 53 DNS resolver in the VPC so instances can resolve domain names. `enable_dns_hostnames` assigns DNS hostnames to EC2 instances with public IPs. Both are required for VPC interface endpoints to work with `private_dns_enabled = true` — without them, the private DNS names for AWS services would not resolve inside the VPC.

---

## Security

**Q: What IAM policies does the node group role need and why?**

A: Three policies are required:
- `AmazonEKSWorkerNodePolicy` — allows nodes to connect to the EKS cluster
- `AmazonEKS_CNI_Policy` — allows vpc-cni to manage ENIs for pod networking
- `AmazonEC2ContainerRegistryReadOnly` — allows nodes to pull images from ECR

No write permissions are given to nodes following least privilege principle.

---

**Q: How are AWS credentials handled in this setup?**

A: Credentials are stored as environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) in each Terraform Cloud workspace, marked as sensitive. They are never stored in code or committed to Git. TFC injects them into the runner environment during plan and apply. This is more secure than storing credentials in `.tfvars` files or local environment.

---
