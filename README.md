# Rent Management System — Infrastructure

Infrastructure and deployment configuration for the **Rent Management System (RMS)** Django application.

This repository contains the Kubernetes configuration required to deploy and run the application with PostgreSQL, persistent storage, Secrets, ConfigMaps, and Ingress.

## Tech Stack

- Docker
- Kubernetes
- PostgreSQL
- Django
- Gunicorn
- NGINX Ingress Controller
- GitHub Actions

## Architecture

```text
                    Internet
                       │
                       │ HTTPS :443
                       ▼
              NGINX Ingress Controller
                       │
                       │ HTTP
                       ▼
                Django Service
                       │
                       ▼
                 Django Pods
                       │
                       │
                       ▼
              PostgreSQL Service
                       │
                       ▼
              PostgreSQL Pod
                       │
                       ▼
             Persistent Storage