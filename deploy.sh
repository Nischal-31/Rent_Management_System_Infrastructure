#!/bin/bash

set -e

# ============================================================
# BidForge Infrastructure + Kubernetes Deployment
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
KUBERNETES_DIR="$PROJECT_ROOT/kubernetes"

INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.ini"

SSH_KEY="$HOME/.ssh/BidForge.pem"

KUBECONFIG_FILE="$ANSIBLE_DIR/bidforge-kubeconfig"

K8S_NAMESPACE="bidforge"
K8S_DEPLOYMENT="bidforge"
K8S_SERVICE="bidforge-service"

CALICO_VERSION="v3.28.0"

# ============================================================
# Helper functions
# ============================================================

log() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

success() {
    echo
    echo "[OK] $1"
}

error() {
    echo
    echo "[ERROR] $1"
    exit 1
}

# ============================================================
# Project information
# ============================================================

clear

echo
echo "============================================================"
echo "             BIDFORGE AUTOMATED DEPLOYMENT"
echo "============================================================"
echo

echo "Project root:"
echo "  $PROJECT_ROOT"

echo "Terraform:"
echo "  $TERRAFORM_DIR"

echo "Ansible:"
echo "  $ANSIBLE_DIR"

echo "Kubernetes:"
echo "  $KUBERNETES_DIR"

# ============================================================
# 1. Check project structure
# ============================================================

log "1. Checking project structure"

[ -d "$TERRAFORM_DIR" ] || error "Terraform directory not found."
[ -d "$ANSIBLE_DIR" ] || error "Ansible directory not found."
[ -d "$KUBERNETES_DIR" ] || error "Kubernetes directory not found."

[ -f "$ANSIBLE_DIR/ansible.cfg" ] \
    || error "ansible.cfg not found."

[ -d "$ANSIBLE_DIR/inventory" ] \
    || error "Ansible inventory directory not found."

[ -d "$ANSIBLE_DIR/playbooks" ] \
    || error "Ansible playbooks directory not found."

[ -f "$ANSIBLE_DIR/playbooks/site.yml" ] \
    || error "Ansible site.yml not found."

success "Project structure verified"

# ============================================================
# 2. Check required commands
# ============================================================

log "2. Checking required commands"

command -v terraform >/dev/null 2>&1 \
    || error "Terraform is not installed."

command -v kubectl >/dev/null 2>&1 \
    || error "kubectl is not installed."

command -v ssh >/dev/null 2>&1 \
    || error "SSH is not available."

command -v scp >/dev/null 2>&1 \
    || error "SCP is not available."

command -v curl >/dev/null 2>&1 \
    || error "curl is not installed."

if ! command -v ansible >/dev/null 2>&1; then

    echo
    echo "[ERROR] Ansible is not installed or not available in PATH."
    echo
    echo "You are running this script inside WSL."
    echo
    echo "Install Ansible with:"
    echo
    echo "  sudo apt update"
    echo "  sudo apt install ansible"
    echo
    echo "Then verify:"
    echo
    echo "  ansible --version"
    echo

    exit 1
fi

success "Required commands found"

# ============================================================
# 3. Check SSH key
# ============================================================

log "3. Checking SSH key"

[ -f "$SSH_KEY" ] \
    || error "SSH key not found: $SSH_KEY"

chmod 600 "$SSH_KEY"

echo "SSH key:"
echo "  $SSH_KEY"

success "SSH key found"

# ============================================================
# 4. Initialize Terraform
# ============================================================

log "4. Initializing Terraform"

cd "$TERRAFORM_DIR"

terraform init

success "Terraform initialized"

# ============================================================
# 5. Format Terraform
# ============================================================

log "5. Formatting Terraform"

terraform fmt

success "Terraform formatted"

# ============================================================
# 6. Validate Terraform
# ============================================================

log "6. Validating Terraform"

terraform validate

success "Terraform configuration is valid"

# ============================================================
# 7. Terraform plan
# ============================================================

log "7. Creating Terraform plan"

terraform plan

# ============================================================
# 8. Terraform apply
# ============================================================

log "8. Applying Terraform infrastructure"

terraform apply -auto-approve

success "Terraform infrastructure applied"

# ============================================================
# 9. Get Terraform outputs
# ============================================================

log "9. Reading Terraform outputs"

INSTANCE_PUBLIC_IP="$(terraform output -raw instance_public_ip)"
INSTANCE_PUBLIC_DNS="$(terraform output -raw instance_public_dns)"
INSTANCE_ID="$(terraform output -raw instance_id)"
VPC_ID="$(terraform output -raw vpc_id)"
SUBNET_ID="$(terraform output -raw subnet_id)"

[ -n "$INSTANCE_PUBLIC_IP" ] \
    || error "Terraform did not return instance_public_ip."

echo
echo "VPC ID:"
echo "  $VPC_ID"

echo
echo "Subnet ID:"
echo "  $SUBNET_ID"

echo
echo "Instance ID:"
echo "  $INSTANCE_ID"

echo
echo "Instance Public IP:"
echo "  $INSTANCE_PUBLIC_IP"

echo
echo "Instance Public DNS:"
echo "  $INSTANCE_PUBLIC_DNS"

success "Terraform outputs retrieved"

# ============================================================
# 10. Wait for EC2 SSH
# ============================================================

log "10. Waiting for EC2 SSH"

SSH_READY=false

for i in {1..30}; do

    echo "SSH attempt $i/30..."

    if ssh \
        -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "ubuntu@$INSTANCE_PUBLIC_IP" \
        "echo SSH_READY" >/dev/null 2>&1; then

        SSH_READY=true
        break
    fi

    sleep 10

done

if [ "$SSH_READY" != true ]; then
    error "EC2 SSH did not become available."
fi

success "EC2 SSH is ready"

# ============================================================
# 11. Update Ansible inventory
# ============================================================

log "11. Updating Ansible inventory"

cat > "$INVENTORY_FILE" <<EOF
[kubernetes]
bidforge-server ansible_host=$INSTANCE_PUBLIC_IP
EOF

echo
echo "Current inventory:"
echo "------------------------------------------------------------"
cat "$INVENTORY_FILE"
echo "------------------------------------------------------------"

success "Ansible inventory updated"

# ============================================================
# 12. Test Ansible connection
# ============================================================

log "12. Testing Ansible connection"

cd "$ANSIBLE_DIR"

ansible -i inventory/hosts.ini kubernetes -m ping

success "Ansible connection successful"

# ============================================================
# 13. Run Ansible provisioning
# ============================================================

log "13. Running Ansible provisioning"

ansible-playbook playbooks/site.yml

success "Ansible provisioning completed"

# ============================================================
# 14. Reset Ansible connection
#
# Important:
#
# If Ansible provisioning adds ubuntu to the docker group,
# the existing SSH session may not know about the new group.
#
# Resetting the connection forces Ansible to establish a
# completely fresh SSH session.
# ============================================================

log "14. Resetting Ansible SSH connection"

ansible kubernetes -m meta -a reset_connection

success "Ansible connection reset"

# ============================================================
# 15. Verify Docker
# ============================================================

log "15. Verifying Docker"

echo
echo "Docker version:"
ansible kubernetes -a "docker --version"

echo
echo "Docker Compose version:"
ansible kubernetes -a "docker compose version"

echo
echo "Docker service:"
ansible kubernetes -a "systemctl is-active docker"

success "Docker service verified"

# ============================================================
# 16. Verify Docker access for ubuntu
# ============================================================

log "16. Verifying Docker access for ubuntu user"

echo
echo "Ubuntu user information:"
ansible kubernetes -a "id ubuntu"

echo
echo "Ubuntu groups:"
ansible kubernetes -a "sudo -u ubuntu -H bash -lc 'id -nG'"

echo
echo "Testing Docker as ubuntu:"
ansible kubernetes -a "sudo -u ubuntu -H docker version"

success "Ubuntu Docker group access verified"

# ============================================================
# 17. Docker hello-world test
# ============================================================

log "17. Running Docker hello-world test"

ansible kubernetes -a "docker run --rm hello-world"

success "Docker hello-world test successful"

# ============================================================
# 18. Verify containerd
# ============================================================

log "18. Verifying containerd"

ansible kubernetes -a "containerd --version"

ansible kubernetes -a "systemctl is-active containerd"

success "Containerd verified"

# ============================================================
# 19. Verify Kubernetes tools
# ============================================================

log "19. Verifying Kubernetes"

ansible kubernetes -a "kubeadm version"

ansible kubernetes -a "kubelet --version"

ansible kubernetes -a "kubectl version --client"

success "Kubernetes tools verified"

# ============================================================
# 20. Initialize Kubernetes cluster
# ============================================================

log "20. Initializing Kubernetes cluster"

if ansible kubernetes -b -m shell \
    -a "test -f /etc/kubernetes/admin.conf" \
    >/dev/null 2>&1; then

    echo
    echo "Kubernetes is already initialized."
    echo "Skipping kubeadm init."

else

    echo
    echo "Kubernetes is not initialized."
    echo "Running kubeadm init..."

    ansible kubernetes -b -a "kubeadm init"

fi

success "Kubernetes cluster initialized"

# ============================================================
# 21. Configure kubeconfig on EC2
# ============================================================

log "21. Configuring kubeconfig on EC2"

ansible kubernetes -b -a \
    "mkdir -p /home/ubuntu/.kube"

ansible kubernetes -b -a \
    "cp -f /etc/kubernetes/admin.conf /home/ubuntu/.kube/config"

ansible kubernetes -b -a \
    "chown ubuntu:ubuntu /home/ubuntu/.kube/config"

success "EC2 kubeconfig configured"

# ============================================================
# 22. Install Calico
# ============================================================

log "22. Installing Calico"

ansible kubernetes -b -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config apply -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml"

success "Calico installed"

# ============================================================
# 23. Remove control-plane taint
# ============================================================

log "23. Configuring single-node Kubernetes"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config taint nodes --all node-role.kubernetes.io/control-plane-" \
    || true

success "Single-node Kubernetes configured"

# ============================================================
# 24. Wait for Kubernetes node
# ============================================================

log "24. Waiting for Kubernetes node"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config wait --for=condition=Ready node --all --timeout=300s"

success "Kubernetes node is Ready"

# ============================================================
# 25. Copy kubeconfig from EC2
# ============================================================

log "25. Copying kubeconfig from EC2"

rm -f "$KUBECONFIG_FILE"

scp \
    -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "ubuntu@$INSTANCE_PUBLIC_IP:/home/ubuntu/.kube/config" \
    "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"

success "Kubeconfig copied"

# ============================================================
# 26. Configure local kubeconfig
#
# The kubeconfig generated by kubeadm normally references
# the EC2 private IP.
#
# We replace it with the EC2 public IP so local kubectl can
# connect from WSL.
#
# insecure-skip-tls-verify is used for this project setup.
# Production should use a proper API server certificate
# containing the public DNS/IP SAN.
# ============================================================

log "26. Configuring kubeconfig"

sed -i \
    '/^[[:space:]]*certificate-authority-data:/d' \
    "$KUBECONFIG_FILE"

sed -i \
    '/^[[:space:]]*certificate-authority:/d' \
    "$KUBECONFIG_FILE"

sed -i \
    "s#^[[:space:]]*server:.*#    server: https://$INSTANCE_PUBLIC_IP:6443#" \
    "$KUBECONFIG_FILE"

sed -i \
    '/^[[:space:]]*insecure-skip-tls-verify:/d' \
    "$KUBECONFIG_FILE"

sed -i \
    '/^[[:space:]]*server: https:\/\//a\    insecure-skip-tls-verify: true' \
    "$KUBECONFIG_FILE"

echo
echo "Kubernetes cluster configuration:"
echo "------------------------------------------------------------"

grep -A4 \
    "server: https://$INSTANCE_PUBLIC_IP:6443" \
    "$KUBECONFIG_FILE" || true

echo "------------------------------------------------------------"

success "Kubeconfig configured"

# ============================================================
# 27. Configure local kubectl
# ============================================================

log "27. Configuring local kubectl"

mkdir -p "$HOME/.kube"

cp "$KUBECONFIG_FILE" "$HOME/.kube/config"

chmod 600 "$HOME/.kube/config"

unset KUBECONFIG

success "Local kubeconfig installed"

# ============================================================
# 28. Test kubectl
# ============================================================

log "28. Testing Kubernetes connection"

kubectl get nodes -o wide

success "kubectl successfully connected to Kubernetes"

# ============================================================
# 29. Create BidForge namespace
# ============================================================

log "29. Creating BidForge namespace"

kubectl create namespace "$K8S_NAMESPACE" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "BidForge namespace ready"

# ============================================================
# 30. Validate Kubernetes manifests
# ============================================================

log "30. Validating Kubernetes manifests"

cd "$KUBERNETES_DIR"

kubectl apply --dry-run=client -f .

success "Kubernetes manifests validated"

# ============================================================
# 31. Deploy Kubernetes manifests
# ============================================================

log "31. Deploying BidForge"

kubectl apply -f .

success "BidForge manifests applied"

# ============================================================
# 32. Wait for PostgreSQL
# ============================================================

log "32. Waiting for PostgreSQL"

kubectl wait \
    --for=condition=Ready \
    pod \
    -l app=postgres \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "PostgreSQL pod is Ready"

# ============================================================
# 33. Verify PostgreSQL connectivity
# ============================================================

log "33. Verifying PostgreSQL connectivity"

POSTGRES_READY=false

for i in {1..30}; do

    echo "PostgreSQL readiness check $i/30..."

    if kubectl exec \
        -n "$K8S_NAMESPACE" \
        deployment/postgres \
        -- pg_isready -U postgres \
        >/dev/null 2>&1; then

        POSTGRES_READY=true
        break
    fi

    sleep 5

done

if [ "$POSTGRES_READY" != true ]; then

    echo
    echo "[ERROR] PostgreSQL did not become ready."
    echo

    echo "PostgreSQL pods:"
    kubectl get pods \
        -n "$K8S_NAMESPACE" \
        -l app=postgres \
        -o wide || true

    echo
    echo "PostgreSQL service:"
    kubectl get service \
        postgres \
        -n "$K8S_NAMESPACE" || true

    echo
    echo "PostgreSQL endpoints:"
    kubectl get endpoints \
        postgres \
        -n "$K8S_NAMESPACE" || true

    echo
    echo "PostgreSQL logs:"
    kubectl logs \
        deployment/postgres \
        -n "$K8S_NAMESPACE" \
        --tail=100 || true

    error "PostgreSQL readiness check failed."

fi

success "PostgreSQL is accepting connections"

# ============================================================
# 34. Wait for BidForge deployment
# ============================================================

log "34. Waiting for BidForge deployment"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "BidForge rollout successful"

# ============================================================
# 35. Verify BidForge -> PostgreSQL connectivity
# ============================================================

log "35. Verifying BidForge database connectivity"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py check --database default

success "BidForge database connection verified"

# ============================================================
# 36. Run Django migrations
# ============================================================

log "36. Running Django migrations"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py migrate --noinput

success "Django migrations completed"

# ============================================================
# 37. Restart BidForge
# ============================================================

log "37. Restarting BidForge"

kubectl rollout restart \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "BidForge restarted"

# ============================================================
# 38. Check BidForge endpoints
# ============================================================

log "38. Checking BidForge endpoints"

kubectl get endpoints \
    "$K8S_SERVICE" \
    -n "$K8S_NAMESPACE"

# ============================================================
# 39. Detect NodePort
# ============================================================

log "39. Detecting NodePort"

NODE_PORT="$(
    kubectl get service "$K8S_SERVICE" \
        -n "$K8S_NAMESPACE" \
        -o jsonpath='{.spec.ports[0].nodePort}'
)"

[ -n "$NODE_PORT" ] \
    || error "Could not determine BidForge NodePort."

echo
echo "BidForge NodePort:"
echo "  $NODE_PORT"

# ============================================================
# 40. Final Kubernetes status
# ============================================================

log "40. Final Kubernetes status"

echo
echo "NODES"
echo "------------------------------------------------------------"

kubectl get nodes -o wide

echo
echo "PODS"
echo "------------------------------------------------------------"

kubectl get pods \
    -n "$K8S_NAMESPACE" \
    -o wide

echo
echo "SERVICES"
echo "------------------------------------------------------------"

kubectl get services \
    -n "$K8S_NAMESPACE"

echo
echo "ENDPOINTS"
echo "------------------------------------------------------------"

kubectl get endpoints \
    -n "$K8S_NAMESPACE"

echo
echo "DEPLOYMENTS"
echo "------------------------------------------------------------"

kubectl get deployments \
    -n "$K8S_NAMESPACE"

# ============================================================
# 41. Test BidForge application
# ============================================================

log "41. Testing BidForge application"

PUBLIC_URL="http://$INSTANCE_PUBLIC_IP:$NODE_PORT"

echo
echo "Testing:"
echo "  $PUBLIC_URL"
echo

if curl \
    --connect-timeout 10 \
    --max-time 30 \
    -f \
    "$PUBLIC_URL" \
    >/dev/null 2>&1; then

    success "BidForge is responding"

else

    echo
    echo "[WARNING] BidForge HTTP test failed."
    echo
    echo "The Kubernetes deployment completed, but the application"
    echo "did not respond to the HTTP request."
    echo
    echo "Useful debugging commands:"
    echo
    echo "  kubectl get pods -n $K8S_NAMESPACE"
    echo
    echo "  kubectl logs deployment/$K8S_DEPLOYMENT -n $K8S_NAMESPACE"
    echo
    echo "  kubectl describe deployment/$K8S_DEPLOYMENT -n $K8S_NAMESPACE"
    echo
    echo "  kubectl get service $K8S_SERVICE -n $K8S_NAMESPACE"
    echo
    echo "  kubectl get endpoints $K8S_SERVICE -n $K8S_NAMESPACE"

fi

# ============================================================
# 42. Final result
# ============================================================

echo
echo
echo "============================================================"
echo "          BIDFORGE DEPLOYMENT COMPLETED"
echo "============================================================"
echo

echo "AWS EC2"
echo "------------------------------------------------------------"
echo "Instance ID : $INSTANCE_ID"
echo "Public IP   : $INSTANCE_PUBLIC_IP"
echo "Public DNS  : $INSTANCE_PUBLIC_DNS"
echo

echo "Kubernetes"
echo "------------------------------------------------------------"
echo "Namespace   : $K8S_NAMESPACE"
echo "Deployment  : $K8S_DEPLOYMENT"
echo "Service     : $K8S_SERVICE"
echo "NodePort    : $NODE_PORT"
echo

echo "BidForge"
echo "------------------------------------------------------------"
echo "URL:"
echo
echo "  $PUBLIC_URL"
echo

echo "Local kubeconfig:"
echo "  $KUBECONFIG_FILE"
echo

echo "============================================================"
echo "              DEPLOYMENT SUCCESSFUL"
echo "============================================================"
echo