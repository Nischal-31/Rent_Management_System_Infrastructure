# BidForge Infrastructure

Infrastructure-as-Code and Kubernetes deployment configuration for **BidForge**, a Django-based smart online auction platform.

This repository manages the infrastructure required to run BidForge on AWS, including cloud provisioning, server configuration, Kubernetes cluster setup, application deployment, PostgreSQL deployment, and service exposure.

The project separates the **application repository** from the **infrastructure repository**.

---

# Architecture

```text
                                      INTERNET
                                         │
                                         │ HTTP
                                         ▼
                              ┌─────────────────────┐
                              │      AWS EC2        │
                              │    Public IP        │
                              └──────────┬──────────┘
                                         │
                                         │ NodePort :31362
                                         ▼
                              ┌─────────────────────┐
                              │ bidforge-service    │
                              │                     │
                              │ Type: NodePort      │
                              │ Port: 80            │
                              │ NodePort: 31362     │
                              └──────────┬──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │   BidForge Pod      │
                              │                     │
                              │ Django Application  │
                              │ Python              │
                              └──────────┬──────────┘
                                         │
                                         │ PostgreSQL :5432
                                         ▼
                              ┌─────────────────────┐
                              │  postgres-service   │
                              │                     │
                              │ Type: ClusterIP     │
                              │ Port: 5432          │
                              └──────────┬──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │  PostgreSQL Pod     │
                              │                     │
                              │ PostgreSQL 16       │
                              └─────────────────────┘
```

### Service separation

BidForge uses a separate Kubernetes Service for each application component:

```text
                         Kubernetes Cluster
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
                 ▼                             ▼
        bidforge-service                postgres-service
           NodePort                       ClusterIP
                 │                             │
                 ▼                             ▼
          BidForge Pod                  PostgreSQL Pod
          Django App                    PostgreSQL DB
                 │
                 └──────────────► postgres-service:5432
```

The Django application is externally accessible through the `NodePort` service.

PostgreSQL uses a `ClusterIP` service and is therefore accessible only from inside the Kubernetes cluster.

---

# Infrastructure Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         BIDFORGE ECOSYSTEM                          │
└─────────────────────────────────────────────────────────────────────┘

                         Developer
                             │
                             │ Git Push
                             ▼
                 ┌─────────────────────────┐
                 │ BidForge Application    │
                 │ Repository              │
                 │                         │
                 │ Django                  │
                 │ Dockerfile              │
                 │ GitHub Actions          │
                 └────────────┬────────────┘
                              │
                              │ Build
                              ▼
                 ┌─────────────────────────┐
                 │      Docker Image       │
                 │                         │
                 │      BidForge App       │
                 └────────────┬────────────┘
                              │
                              │ Push
                              ▼
                 ┌─────────────────────────┐
                 │       Docker Hub        │
                 │                         │
                 │   BidForge Image        │
                 └────────────┬────────────┘
                              │
                              │ Pull
                              ▼

┌─────────────────────────────────────────────────────────────────────┐
│                            AWS CLOUD                                │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                           VPC                                │   │
│   │                                                             │   │
│   │   ┌─────────────────────────────────────────────────────┐   │   │
│   │   │                     Subnet                          │   │   │
│   │   │                                                     │   │   │
│   │   │   ┌─────────────────────────────────────────────┐   │   │   │
│   │   │   │                 EC2 Instance                │   │   │   │
│   │   │   │                                             │   │   │   │
│   │   │   │ Ubuntu Linux                               │   │   │   │
│   │   │   │ Docker                                     │   │   │   │
│   │   │   │ containerd                                 │   │   │   │
│   │   │   │ kubelet                                    │   │   │   │
│   │   │   │ kubeadm                                    │   │   │   │
│   │   │   │ kubectl                                    │   │   │   │
│   │   │   │                                             │   │   │   │
│   │   │   │         Kubernetes Cluster                  │   │   │   │
│   │   │   │                                             │   │   │   │
│   │   │   │    ┌──────────────────────────────┐         │   │   │   │
│   │   │   │    │ BidForge Deployment         │         │   │   │   │
│   │   │   │    │                              │         │   │   │   │
│   │   │   │    │      BidForge Pod            │         │   │   │   │
│   │   │   │    │      Django Application      │         │   │   │   │
│   │   │   │    └──────────────┬───────────────┘         │   │   │   │
│   │   │   │                   │                         │   │   │   │
│   │   │   │                   ▼                         │   │   │   │
│   │   │   │          postgres-service                  │   │   │   │
│   │   │   │                   │                         │   │   │   │
│   │   │   │                   ▼                         │   │   │   │
│   │   │   │    ┌──────────────────────────────┐         │   │   │   │
│   │   │   │    │ PostgreSQL Deployment       │         │   │   │   │
│   │   │   │    │                              │         │   │   │   │
│   │   │   │    │      PostgreSQL Pod          │         │   │   │   │
│   │   │   │    └──────────────────────────────┘         │   │   │   │
│   │   │   │                                             │   │   │   │
│   │   │   └─────────────────────────────────────────────┘   │   │
│   │   │                                                     │   │
│   │   └─────────────────────────────────────────────────────┘   │
│   │                                                             │
│   └─────────────────────────────────────────────────────────────┘
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

# Repository Structure

```text
BidForge-Infrastructure/
│
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── ...
│
├── ansible/
│   ├── ansible.cfg
│   │
│   ├── inventory/
│   │   └── hosts.ini
│   │
│   ├── playbooks/
│   │   └── site.yml
│   │
│   └── ...
│
├── kubernetes/
│   ├── namespace.yaml
│   │
│   ├── bidforge-deployment.yaml
│   ├── bidforge-service.yaml
│   │
│   ├── postgres-deployment.yaml
│   ├── postgres-service.yaml
│   │
│   └── ...
│
├── docs/
│   └── ...
│
├── deploy.sh
│
└── README.md
```

---

# Repository Responsibilities

This repository is responsible for the infrastructure and deployment environment.

### Terraform

Terraform provisions the AWS infrastructure.

```text
Terraform
    │
    ├── VPC
    ├── Subnet
    ├── Networking
    ├── Security Configuration
    └── EC2
```

### Ansible

Ansible configures the EC2 server.

```text
Ansible
    │
    ├── Docker
    ├── Docker Compose
    ├── containerd
    ├── kubeadm
    ├── kubelet
    └── kubectl
```

### Kubernetes

Kubernetes manages the application containers.

```text
Kubernetes
    │
    ├── BidForge Deployment
    ├── BidForge Service
    ├── PostgreSQL Deployment
    ├── PostgreSQL Service
    ├── Namespace
    └── Calico Networking
```

### deploy.sh

The deployment script orchestrates the infrastructure workflow.

```text
deploy.sh
    │
    ├── Terraform
    │
    ├── Ansible
    │
    └── Kubernetes
```

---

# Application Repository vs Infrastructure Repository

BidForge is intentionally divided into two repositories.

## BidForge Application Repository

The application repository contains the actual Django application.

```text
BidForge Application
        │
        ├── Django
        ├── Python
        ├── Templates
        ├── Models
        ├── APIs
        ├── Dockerfile
        │
        ▼
   GitHub Actions
        │
        ▼
   Docker Image
        │
        ▼
    Docker Hub
```

Its primary responsibilities are:

* Application development
* Testing
* Docker image creation
* Container image publishing
* Application CI/CD

---

## BidForge Infrastructure Repository

This repository manages:

```text
AWS Infrastructure
        │
        ├── Terraform
        │
        ├── Ansible
        │
        ├── Kubernetes
        │
        └── Deployment Automation
```

Its primary responsibilities are:

* AWS infrastructure
* EC2 configuration
* Kubernetes cluster
* Kubernetes manifests
* PostgreSQL deployment
* Application deployment environment

---

# Complete Deployment Flow

```text
                         Developer
                             │
                             ▼
                      GitHub Repository
                             │
                             ▼
                    GitHub Actions
                             │
                     Build & Test
                             │
                             ▼
                     Docker Build
                             │
                             ▼
                        Docker Hub
                             │
                             │
                             │
             ┌───────────────┘
             │
             ▼
    Infrastructure Repository
             │
             ▼
          Terraform
             │
             ▼
       AWS Infrastructure
             │
             ▼
          EC2 Server
             │
             ▼
           Ansible
             │
             ▼
 Docker + containerd + Kubernetes
             │
             ▼
      Kubernetes Cluster
             │
       ┌─────┴─────┐
       │           │
       ▼           ▼
   BidForge    PostgreSQL
      Pod          Pod
       │           │
       │           │
       ▼           ▼
BidForge Service  postgres-service
   NodePort          ClusterIP
       │
       ▼
    Internet
```

---

# Technology Stack

## Cloud Infrastructure

| Technology      | Purpose                |
| --------------- | ---------------------- |
| AWS             | Cloud infrastructure   |
| EC2             | Kubernetes host        |
| VPC             | Network isolation      |
| Subnet          | Network segmentation   |
| Security Groups | Network access control |

## Infrastructure as Code

| Technology | Purpose                               |
| ---------- | ------------------------------------- |
| Terraform  | AWS infrastructure provisioning       |
| Ansible    | Server configuration and provisioning |
| Bash       | Deployment orchestration              |

## Containerization

| Technology | Purpose                             |
| ---------- | ----------------------------------- |
| Docker     | Container runtime/build environment |
| Docker Hub | Container image registry            |
| containerd | Kubernetes container runtime        |

## Kubernetes

| Technology | Purpose                        |
| ---------- | ------------------------------ |
| Kubernetes | Container orchestration        |
| kubeadm    | Cluster initialization         |
| kubelet    | Node agent                     |
| kubectl    | Cluster management             |
| Calico     | Pod networking                 |
| NodePort   | External application access    |
| ClusterIP  | Internal service communication |

## Application

| Technology | Purpose              |
| ---------- | -------------------- |
| Django     | Web application      |
| Python     | Application language |
| PostgreSQL | Relational database  |

---

# Kubernetes Architecture

The current deployment uses a **single-node Kubernetes cluster** running on an AWS EC2 instance.

```text
                    Kubernetes Cluster
                           │
                           ▼
                  ┌─────────────────┐
                  │    EC2 Node     │
                  │                 │
                  │ Control Plane   │
                  │       +         │
                  │     Worker      │
                  └────────┬────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       ┌───────────────┐        ┌───────────────┐
       │ BidForge Pod  │        │ PostgreSQL Pod │
       │               │        │               │
       │ Django        │        │ PostgreSQL 16  │
       └───────┬───────┘        └───────┬───────┘
               │                        │
               │                        │
               ▼                        ▼
       ┌───────────────┐        ┌───────────────┐
       │bidforge-service│       │postgres-service│
       │               │        │               │
       │ NodePort      │        │ ClusterIP      │
       └───────┬───────┘        └───────┬───────┘
               │                        │
               │                        │
               ▼                        │
            Internet                    │
                                        │
                    BidForge ───────────┘
```

---

# Kubernetes Services

Each major component has its own Kubernetes Service.

## BidForge Service

```yaml
type: NodePort
```

Purpose:

* Exposes the Django application outside the cluster.
* Routes external traffic to BidForge pods.

Example:

```text
EC2_PUBLIC_IP:31362
        │
        ▼
bidforge-service
        │
        ▼
BidForge Pod
```

---

## PostgreSQL Service

```yaml
type: ClusterIP
```

Purpose:

* Provides internal database connectivity.
* Keeps PostgreSQL inaccessible directly from the Internet.

Example:

```text
BidForge Pod
     │
     │ postgres:5432
     ▼
postgres-service
     │
     ▼
PostgreSQL Pod
```

This separation ensures that the database is not directly exposed through a public NodePort.

---

# Networking

The application uses two different networking paths.

## External Traffic

```text
Internet
   │
   ▼
AWS EC2 Public IP
   │
   ▼
NodePort
   │
   ▼
bidforge-service
   │
   ▼
BidForge Pod
```

## Internal Database Traffic

```text
BidForge Pod
     │
     │ TCP :5432
     ▼
postgres-service
     │
     ▼
PostgreSQL Pod
```

The PostgreSQL service is internal to the Kubernetes cluster.

---

# Infrastructure Layers

The project follows a layered infrastructure architecture.

```text
┌───────────────────────────────┐
│       Application Layer       │
│                               │
│        Django / BidForge      │
└───────────────┬───────────────┘
                │
┌───────────────▼───────────────┐
│       Container Layer         │
│                               │
│            Docker             │
└───────────────┬───────────────┘
                │
┌───────────────▼───────────────┐
│      Orchestration Layer      │
│                               │
│          Kubernetes           │
└───────────────┬───────────────┘
                │
┌───────────────▼───────────────┐
│    Configuration Layer        │
│                               │
│           Ansible             │
└───────────────┬───────────────┘
                │
┌───────────────▼───────────────┐
│     Infrastructure Layer      │
│                               │
│           Terraform           │
└───────────────┬───────────────┘
                │
┌───────────────▼───────────────┐
│          AWS Cloud            │
│                               │
│       VPC + EC2 + Network     │
└───────────────────────────────┘
```

---

# Deployment Automation

The primary deployment entry point is:

```bash
./deploy.sh
```

The script connects the infrastructure layers:

```text
Terraform
    ↓
AWS EC2
    ↓
Ansible
    ↓
Docker / containerd
    ↓
Kubernetes
    ↓
BidForge + PostgreSQL
    ↓
Services
```

Make the script executable if required:

```bash
chmod +x deploy.sh
```

Then run:

```bash
./deploy.sh
```

---

# Prerequisites

The deployment environment requires:

* AWS account
* AWS CLI
* Terraform
* Ansible
* kubectl
* SSH
* SCP
* curl
* Git
* WSL/Ubuntu when running from Windows

AWS credentials should be configured before deployment.

```bash
aws configure
```

The EC2 SSH private key should be available at:

```text
~/.ssh/BidForge.pem
```

The key permissions should be restricted:

```bash
chmod 600 ~/.ssh/BidForge.pem
```

---

# Ansible

Ansible is used to configure the AWS EC2 instance.

The inventory contains the Kubernetes server:

```ini
[kubernetes]
bidforge-server ansible_host=<EC2_PUBLIC_IP>
```

Test connectivity:

```bash
ansible kubernetes -m ping
```

Reset the current Ansible SSH session when required:

```bash
ansible kubernetes -m meta -a reset_connection
```

Verify Docker:

```bash
ansible kubernetes -a "docker --version"
```

Verify Docker Compose:

```bash
ansible kubernetes -a "docker compose version"
```

Verify Docker service:

```bash
ansible kubernetes -a "systemctl is-active docker"
```

Test Docker:

```bash
ansible kubernetes -a "docker run --rm hello-world"
```

---

# Terraform

Terraform manages the AWS infrastructure.

Typical outputs include:

```text
instance_id
instance_public_ip
instance_public_dns
vpc_id
subnet_id
```

These outputs are used by the deployment process to configure Ansible and Kubernetes.

Terraform workflow:

```text
terraform init
        ↓
terraform fmt
        ↓
terraform validate
        ↓
terraform plan
        ↓
terraform apply
```

---

# Kubernetes Deployment

Kubernetes manifests are stored in:

```text
kubernetes/
```

The deployment contains separate resources for the application and database.

```text
kubernetes/
│
├── namespace.yaml
│
├── bidforge-deployment.yaml
├── bidforge-service.yaml
│
├── postgres-deployment.yaml
├── postgres-service.yaml
│
└── ...
```

Check the Kubernetes cluster:

```bash
kubectl get nodes
```

Check all BidForge resources:

```bash
kubectl get all -n bidforge
```

Check pods:

```bash
kubectl get pods -n bidforge -o wide
```

Check services:

```bash
kubectl get svc -n bidforge
```

Expected structure:

```text
NAME               TYPE        PORT(S)
bidforge-service   NodePort    80:31362/TCP
postgres           ClusterIP   5432/TCP
```

---

# Useful Kubernetes Commands

## Nodes

```bash
kubectl get nodes -o wide
```

## Pods

```bash
kubectl get pods -n bidforge -o wide
```

## Services

```bash
kubectl get svc -n bidforge
```

## Deployments

```bash
kubectl get deployments -n bidforge
```

## Endpoints

```bash
kubectl get endpoints -n bidforge
```

## BidForge logs

```bash
kubectl logs deployment/bidforge -n bidforge
```

## PostgreSQL logs

```bash
kubectl logs deployment/postgres -n bidforge
```

## Describe BidForge

```bash
kubectl describe deployment/bidforge -n bidforge
```

## Describe PostgreSQL

```bash
kubectl describe deployment/postgres -n bidforge
```

## Deployment status

```bash
kubectl rollout status deployment/bidforge -n bidforge
```

## Restart BidForge

```bash
kubectl rollout restart deployment/bidforge -n bidforge
```

## Django migrations

```bash
kubectl exec -n bidforge deployment/bidforge -- python manage.py migrate
```

## Django shell

```bash
kubectl exec -it -n bidforge deployment/bidforge -- python manage.py shell
```

---

# PostgreSQL Connectivity

The Django application connects to PostgreSQL through the Kubernetes Service.

The database hostname should be the Kubernetes service name:

```text
postgres
```

The database port is:

```text
5432
```

Therefore, from the BidForge container, PostgreSQL is accessed through:

```text
postgres:5432
```

The traffic remains inside the Kubernetes cluster.

```text
BidForge
   │
   ▼
postgres:5432
   │
   ▼
PostgreSQL Service
   │
   ▼
PostgreSQL Pod
```

---

# Database Verification

Check the PostgreSQL pod:

```bash
kubectl get pods -n bidforge -l app=postgres
```

Check the PostgreSQL service:

```bash
kubectl get svc postgres -n bidforge
```

Check the PostgreSQL endpoints:

```bash
kubectl get endpoints postgres -n bidforge
```

Test PostgreSQL readiness:

```bash
kubectl exec -n bidforge deployment/postgres -- pg_isready -U postgres
```

---

# Application Verification

After deployment, retrieve the NodePort:

```bash
kubectl get svc bidforge-service -n bidforge
```

Example:

```text
bidforge-service   NodePort   10.111.29.204   <none>   80:31362/TCP
```

The application can then be accessed through:

```text
http://<EC2_PUBLIC_IP>:31362
```

The NodePort may change depending on the Kubernetes configuration.

---

# Deployment Verification

A successful deployment should show:

```text
NODES
-----------------------------------------------
NAME            STATUS   ROLES
ip-10-0-1-93    Ready    control-plane
```

BidForge:

```text
NAME                       READY   STATUS
bidforge-xxxxxxxxxx-xxxxx  1/1     Running
```

PostgreSQL:

```text
NAME                       READY   STATUS
postgres-xxxxxxxxxx-xxxxx  1/1     Running
```

Services:

```text
NAME               TYPE        PORT(S)
bidforge-service   NodePort    80:31362/TCP
postgres           ClusterIP   5432/TCP
```

---

# DevOps Workflow

The complete workflow can be summarized as:

```text
                    ┌──────────────┐
                    │   Developer  │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │    GitHub    │
                    └──────┬───────┘
                           │
                           ▼
                 ┌────────────────────┐
                 │ GitHub Actions     │
                 │                    │
                 │ Test               │
                 │ Build              │
                 │ Docker Image       │
                 └─────────┬──────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Docker Hub  │
                    └──────┬───────┘
                           │
                           │ Image
                           ▼
                  ┌─────────────────┐
                  │ Infrastructure  │
                  │ Repository      │
                  └───────┬─────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
        ┌───────────┐           ┌───────────┐
        │ Terraform │           │  Ansible  │
        └─────┬─────┘           └─────┬─────┘
              │                       │
              └───────────┬───────────┘
                          ▼
                     AWS EC2
                          │
                          ▼
                    Kubernetes
                          │
                ┌─────────┴─────────┐
                │                   │
                ▼                   ▼
          BidForge Pod        PostgreSQL Pod
                │                   │
                ▼                   ▼
      bidforge-service       postgres-service
          NodePort               ClusterIP
                │
                ▼
             Internet
```

---

# Security Considerations

The current architecture keeps PostgreSQL internal to Kubernetes.

```text
Internet
   │
   ▼
BidForge NodePort
   │
   ▼
Django
   │
   ▼
PostgreSQL ClusterIP
```

PostgreSQL does not have a public NodePort.

For a production deployment, additional security improvements should be considered:

* HTTPS/TLS
* Kubernetes Secrets
* AWS Secrets Manager
* Restricted EC2 security groups
* Private database networking
* Network Policies
* Container image scanning
* RBAC
* Non-root containers
* Pod Security Standards
* Ingress Controller
* AWS Load Balancer
* Managed PostgreSQL through Amazon RDS

---

# Current Infrastructure Model

The current project uses:

```text
AWS
 │
 └── EC2
      │
      └── Kubernetes
           │
           ├── BidForge Deployment
           │    └── BidForge Pod
           │         └── Django
           │
           ├── BidForge Service
           │    └── NodePort
           │
           ├── PostgreSQL Deployment
           │    └── PostgreSQL Pod
           │
           └── PostgreSQL Service
                └── ClusterIP
```

This is a **single-node Kubernetes architecture**.

It is suitable for:

* Development
* Learning
* Demonstration
* Portfolio projects
* Small-scale deployments

For high availability and production workloads, the architecture should be expanded to multiple nodes and managed infrastructure.

---

# Future Improvements

Potential future improvements include:

### Kubernetes

* Multi-node cluster
* Horizontal Pod Autoscaler
* Ingress Controller
* Network Policies
* Persistent Volumes
* StatefulSet for PostgreSQL

### AWS

* Amazon RDS PostgreSQL
* Application Load Balancer
* Route 53
* ACM TLS certificates
* Private subnets
* NAT Gateway

### CI/CD

* Automated Kubernetes deployment
* GitOps
* Argo CD
* Automated rollback
* Environment separation
* Staging and production environments

### Security

* AWS Secrets Manager
* Kubernetes Secrets
* Trivy image scanning
* RBAC
* Pod security
* Network policies

### Monitoring

* Prometheus
* Grafana
* Loki
* Centralized logging
* Alerting

---

# Project Goals

BidForge Infrastructure demonstrates a complete DevOps and cloud deployment workflow using:

```text
Terraform
    +
Ansible
    +
Docker
    +
Docker Hub
    +
Kubernetes
    +
AWS
    +
Django
    +
PostgreSQL
```

The project demonstrates how a containerized Django application can be deployed to Kubernetes on AWS using Infrastructure as Code, configuration management, containerization, and Kubernetes orchestration.

---

# Related Repositories

### BidForge Application

The application repository contains:

* Django source code
* Application configuration
* Dockerfile
* GitHub Actions
* Container image build
* Docker Hub publishing

### BidForge Infrastructure

This repository contains:

* Terraform
* Ansible
* Kubernetes manifests
* AWS infrastructure
* Deployment automation
* Kubernetes application and database services

---

# Author

**Nischal Moktan**

**BidForge — Smart Online Auction Platform**

Infrastructure & DevOps
