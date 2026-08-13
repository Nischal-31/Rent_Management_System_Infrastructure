#!/bin/bash

set -e

# ============================================================
# Rent Management System Infrastructure + Kubernetes Deployment
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
KUBERNETES_DIR="$PROJECT_ROOT/kubernetes"

INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.ini"

SSH_KEY="$HOME/.ssh/BidForge.pem"

KUBECONFIG_FILE="$ANSIBLE_DIR/rms-kubeconfig"

K8S_NAMESPACE="rent-management-system"
K8S_DEPLOYMENT="rms-deployment"
K8S_SERVICE="rms-service"

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
echo "       RENT MANAGEMENT SYSTEM AUTOMATED DEPLOYMENT"
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

[ -f "$ANSIBLE_DIR/ansible.cfg" ] || error "ansible.cfg not found."
[ -d "$ANSIBLE_DIR/inventory" ] || error "Ansible inventory directory not found."
[ -d "$ANSIBLE_DIR/playbooks" ] || error "Ansible playbooks directory not found."
[ -f "$ANSIBLE_DIR/playbooks/site.yml" ] || error "Ansible site.yml not found."

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
rms-server ansible_host=$INSTANCE_PUBLIC_IP
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
# 14. Reset Ansible SSH connection
# ============================================================

log "14. Resetting Ansible SSH connection"

ansible kubernetes -m meta -a reset_connection

success "Ansible connection reset"

# ============================================================
# 15. Verify containerd
# ============================================================

log "15. Verifying containerd"

ansible kubernetes -a "containerd --version"

ansible kubernetes -a "systemctl is-active containerd"

success "Containerd verified"

# ============================================================
# 16. Verify Kubernetes tools
# ============================================================

log "16. Verifying Kubernetes tools"

ansible kubernetes -a "kubeadm version"

ansible kubernetes -a "kubelet --version"

ansible kubernetes -a "kubectl version --client"

success "Kubernetes tools verified"

# ============================================================
# 17. Initialize Kubernetes cluster
# ============================================================

log "17. Initializing Kubernetes cluster"

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
# 18. Configure kubeconfig on EC2
# ============================================================

log "18. Configuring kubeconfig on EC2"

ansible kubernetes -b -a \
    "mkdir -p /home/ubuntu/.kube"

ansible kubernetes -b -a \
    "cp -f /etc/kubernetes/admin.conf /home/ubuntu/.kube/config"

ansible kubernetes -b -a \
    "chown ubuntu:ubuntu /home/ubuntu/.kube/config"

success "EC2 kubeconfig configured"

# ============================================================
# 19. Install Calico
# ============================================================

log "19. Installing Calico"

ansible kubernetes -b -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config apply -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml"

success "Calico installed"

# ============================================================
# 20. Remove control-plane taint
# ============================================================

log "20. Configuring single-node Kubernetes"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config taint nodes --all node-role.kubernetes.io/control-plane-" \
    || true

success "Single-node Kubernetes configured"

# ============================================================
# 21. Wait for Kubernetes node
# ============================================================

log "21. Waiting for Kubernetes node"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config wait --for=condition=Ready node --all --timeout=300s"

success "Kubernetes node is Ready"

# ============================================================
# 22. Show Kubernetes nodes and pods
# ============================================================

log "22. Checking Kubernetes cluster"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config get nodes -o wide"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config get pods -A"

success "Kubernetes cluster verified"

# ============================================================
# 23. Copy kubeconfig from EC2
# ============================================================

log "23. Copying kubeconfig from EC2"

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
# 24. Configure local kubeconfig
# ============================================================

log "24. Configuring local kubeconfig"

# Remove certificate-authority-data
sed -i '/certificate-authority-data:/d' "$KUBECONFIG_FILE"

# Remove certificate-authority
sed -i '/certificate-authority:/d' "$KUBECONFIG_FILE"

# Replace Kubernetes API server address
sed -i "s|^[[:space:]]*server:.*|    server: https://$INSTANCE_PUBLIC_IP:6443|" "$KUBECONFIG_FILE"

# Remove existing insecure-skip-tls-verify entries
sed -i '/insecure-skip-tls-verify:/d' "$KUBECONFIG_FILE"

# Add insecure TLS setting immediately after server
sed -i "/server: https:\/\/$INSTANCE_PUBLIC_IP:6443/a\\    insecure-skip-tls-verify: true" "$KUBECONFIG_FILE"

echo
echo "Kubernetes cluster configuration:"
echo "------------------------------------------------------------"

grep -A5 "server: https://$INSTANCE_PUBLIC_IP:6443" "$KUBECONFIG_FILE" || true

echo "------------------------------------------------------------"

success "Kubeconfig configured"

# ============================================================
# 25. Configure local kubectl
# ============================================================

log "25. Configuring local kubectl"

mkdir -p "$HOME/.kube"

cp "$KUBECONFIG_FILE" "$HOME/.kube/config"

chmod 600 "$HOME/.kube/config"

unset KUBECONFIG

success "Local kubeconfig installed"

# ============================================================
# 26. Test kubectl
# ============================================================

log "26. Testing Kubernetes connection"

kubectl get nodes -o wide

success "kubectl successfully connected to Kubernetes"

# ============================================================
# 27. Create RMS namespace
# ============================================================

log "27. Creating RMS namespace"

kubectl create namespace "$K8S_NAMESPACE" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "RMS namespace ready"

# ============================================================
# 28. Validate Kubernetes manifests
# ============================================================

log "28. Validating Kubernetes manifests"

cd "$KUBERNETES_DIR"

kubectl apply \
    --dry-run=client \
    -f .

success "Kubernetes manifests validated"

# ============================================================
# 29. Deploy Kubernetes manifests
# ============================================================

log "29. Deploying Rent Management System"

kubectl apply -f .

success "RMS Kubernetes manifests applied"

# ============================================================
# 30. Show RMS pods
# ============================================================

log "30. Checking RMS pods"

kubectl get pods \
    -n "$K8S_NAMESPACE" \
    -o wide

success "RMS pods created"

# ============================================================
# 31. Wait for PostgreSQL
# ============================================================

log "31. Waiting for PostgreSQL"

kubectl wait \
    --for=condition=Ready \
    pod \
    -l app=postgres \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "PostgreSQL pod is Ready"

# ============================================================
# 32. Verify PostgreSQL connectivity
# ============================================================

log "32. Verifying PostgreSQL connectivity"

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
# 33. Wait for RMS deployment
# ============================================================

log "33. Waiting for RMS deployment"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "RMS rollout successful"

# ============================================================
# 34. Check RMS environment variables
# ============================================================

log "34. Checking RMS environment"

echo
echo "DATABASE_URL:"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- printenv DATABASE_URL || true

echo
echo "DEBUG:"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- printenv DEBUG || true

echo
echo "ALLOWED_HOSTS:"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python -c \
    "from django.conf import settings; print(settings.ALLOWED_HOSTS)" || true

success "RMS environment checked"

# ============================================================
# 35. Update ALLOWED_HOSTS with current EC2 IP
# ============================================================

log "35. Verifying current EC2 host"

echo
echo "Current EC2 public IP:"
echo "  $INSTANCE_PUBLIC_IP"

echo
echo "Django must allow:"
echo "  $INSTANCE_PUBLIC_IP"

success "Current EC2 host identified"

# ============================================================
# 36. Verify RMS database connectivity
# ============================================================

log "36. Verifying RMS database connectivity"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py check --database default

success "RMS database connection verified"

# ============================================================
# 37. Run Django migrations
# ============================================================

log "37. Running Django migrations"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py migrate --noinput

success "Django migrations completed"

# ============================================================
# 38. Restart RMS after migrations
# ============================================================

log "38. Restarting RMS"

kubectl rollout restart \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "RMS restarted"

# ============================================================
# 38. Check RMS endpoints
# ============================================================

log "38. Checking RMS endpoints"

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
    || error "Could not determine RMS NodePort."

echo
echo "RMS NodePort:"
echo "  $NODE_PORT"

# ============================================================
# 40. Configure dynamic Django hosts
# ============================================================

log "40. Configuring dynamic Django hosts"

PUBLIC_URL="http://$INSTANCE_PUBLIC_IP:$NODE_PORT"

echo
echo "Current EC2 public IP:"
echo "  $INSTANCE_PUBLIC_IP"

echo
echo "Current NodePort:"
echo "  $NODE_PORT"

echo
echo "Public application URL:"
echo "  $PUBLIC_URL"

# ------------------------------------------------------------
# Build ALLOWED_HOSTS
# ------------------------------------------------------------

ALLOWED_HOSTS_VALUE="\
$INSTANCE_PUBLIC_IP,\
localhost,\
127.0.0.1,\
rent-management-system-1wyn.onrender.com,\
www.bikashgosain.com.np,\
bikashgosain.com.np,\
.onrender.com"

# ------------------------------------------------------------
# Build CSRF_TRUSTED_ORIGINS
# ------------------------------------------------------------

CSRF_TRUSTED_ORIGINS_VALUE="\
http://$INSTANCE_PUBLIC_IP:$NODE_PORT,\
http://$INSTANCE_PUBLIC_IP,\
https://rent-management-system-1wyn.onrender.com,\
https://www.bikashgosain.com.np,\
https://bikashgosain.com.np"

echo
echo "ALLOWED_HOSTS:"
echo "  $ALLOWED_HOSTS_VALUE"

echo
echo "CSRF_TRUSTED_ORIGINS:"
echo "  $CSRF_TRUSTED_ORIGINS_VALUE"

# ------------------------------------------------------------
# Update ConfigMap
# ------------------------------------------------------------

kubectl create configmap rms-config \
    -n "$K8S_NAMESPACE" \
    --from-literal="ALLOWED_HOSTS=$ALLOWED_HOSTS_VALUE" \
    --from-literal="CSRF_TRUSTED_ORIGINS=$CSRF_TRUSTED_ORIGINS_VALUE" \
    --from-literal="DEBUG=False" \
    --from-literal="DJANGO_ALLOWED_HOSTS=$INSTANCE_PUBLIC_IP localhost 127.0.0.1" \
    --from-literal="EMAIL_HOST_USER=bikashgosain0@gmail.com" \
    --from-literal="GOOGLE_CLIENT_ID=14664610456-a9sa2e5taevfrq43agip779713r8rafv.apps.googleusercontent.com" \
    --from-literal="TWILIO_PHONE_NUMBER=+1234567890" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "Dynamic Django host configuration applied"

# ============================================================
# 41. Restart RMS to load ConfigMap
# ============================================================

log "41. Restarting RMS with updated environment"

kubectl rollout restart \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "RMS restarted with updated Django configuration"

# ============================================================
# 42. Verify Django environment
# ============================================================

log "42. Verifying Django environment"

echo
echo "ALLOWED_HOSTS:"
kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- printenv ALLOWED_HOSTS || true

echo
echo "CSRF_TRUSTED_ORIGINS:"
kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- printenv CSRF_TRUSTED_ORIGINS || true

echo
echo "DEBUG:"
kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- printenv DEBUG || true

echo
echo "Django resolved ALLOWED_HOSTS:"
kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python -c \
    "from django.conf import settings; print(settings.ALLOWED_HOSTS)"

success "Django environment verified"

# ============================================================
# 43. Verify RMS database connectivity
# ============================================================

log "43. Verifying RMS database connectivity"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py check --database default

success "RMS database connection verified"

# ============================================================
# 44. Run Django migrations
# ============================================================

log "44. Running Django migrations"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py migrate --noinput

success "Django migrations completed"

# ============================================================
# 45. Create default Django superuser
# ============================================================

log "45. Creating default Django superuser"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py create_superuser_default

success "Default Django superuser created/verified"

# ============================================================
# 46. Check RMS endpoints
# ============================================================

log "46. Checking RMS endpoints"

kubectl get endpoints \
    "$K8S_SERVICE" \
    -n "$K8S_NAMESPACE"

# ============================================================
# 47. Final Kubernetes status
# ============================================================

log "47. Final Kubernetes status"

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
# 48. Test RMS application
# ============================================================

log "48. Testing RMS application"

echo
echo "Testing:"
echo "  $PUBLIC_URL"
echo

HTTP_STATUS="$(
    curl \
        --connect-timeout 10 \
        --max-time 30 \
        -s \
        -o /dev/null \
        -w "%{http_code}" \
        "$PUBLIC_URL" \
        || echo "000"
)"

echo
echo "HTTP Status:"
echo "  $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ]; then

    success "RMS is responding with HTTP 200"

else

    echo
    echo "[WARNING] RMS returned HTTP $HTTP_STATUS"
    echo
    echo "Useful debugging commands:"
    echo
    echo "  kubectl logs deployment/$K8S_DEPLOYMENT -n $K8S_NAMESPACE"
    echo
    echo "  kubectl logs deployment/$K8S_DEPLOYMENT -n $K8S_NAMESPACE --tail=100"
    echo
    echo "  kubectl get pods -n $K8S_NAMESPACE -o wide"
    echo
    echo "  kubectl get service $K8S_SERVICE -n $K8S_NAMESPACE"
    echo
    echo "  kubectl get endpoints $K8S_SERVICE -n $K8S_NAMESPACE"
    echo
fi

# ============================================================
# 49. Final result
# ============================================================

echo
echo
echo "============================================================"
echo "       RENT MANAGEMENT SYSTEM DEPLOYMENT COMPLETED"
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

echo "Rent Management System"
echo "------------------------------------------------------------"
echo "URL:"
echo
echo "  $PUBLIC_URL"
echo

echo "Local kubeconfig:"
echo "  $KUBECONFIG_FILE"
echo

echo "============================================================"
echo "             DEPLOYMENT SUCCESSFUL"
echo "============================================================"

# ============================================================
# 50. Live RMS application logs
# ============================================================

echo
echo
echo "============================================================"
echo "                 LIVE RMS APPLICATION LOGS"
echo "============================================================"
echo
echo "Starting live logs for:"
echo "  deployment/$K8S_DEPLOYMENT"
echo
echo "Press Ctrl+C to stop watching logs."
echo
echo "============================================================"
echo

kubectl logs \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    --tail=100 \
    -f