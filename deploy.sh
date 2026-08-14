#!/bin/bash

set -e

# ============================================================
# Rent Management System
# Infrastructure + Kubernetes Automated Deployment
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
# 1. Project information
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
# 2. Check project structure
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
# 3. Check required commands
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

command -v base64 >/dev/null 2>&1 \
    || error "base64 is not installed."

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
# 4. Check SSH key
# ============================================================

log "3. Checking SSH key"

[ -f "$SSH_KEY" ] \
    || error "SSH key not found: $SSH_KEY"

chmod 600 "$SSH_KEY"

echo "SSH key:"
echo "  $SSH_KEY"

success "SSH key found"

# ============================================================
# 5. Initialize Terraform
# ============================================================

log "4. Initializing Terraform"

cd "$TERRAFORM_DIR"

terraform init

success "Terraform initialized"

# ============================================================
# 6. Format Terraform
# ============================================================

log "5. Formatting Terraform"

terraform fmt

success "Terraform formatted"

# ============================================================
# 7. Validate Terraform
# ============================================================

log "6. Validating Terraform"

terraform validate

success "Terraform configuration is valid"

# ============================================================
# 8. Terraform plan
# ============================================================

log "7. Creating Terraform plan"

terraform plan

# ============================================================
# 9. Terraform apply
# ============================================================

log "8. Applying Terraform infrastructure"

terraform apply -auto-approve

success "Terraform infrastructure applied"

# ============================================================
# 10. Get Terraform outputs
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
# 11. Wait for EC2 SSH
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
# 12. Update Ansible inventory
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
# 13. Test Ansible connection
# ============================================================

log "12. Testing Ansible connection"

cd "$ANSIBLE_DIR"

ansible -i inventory/hosts.ini kubernetes -m ping

success "Ansible connection successful"

# ============================================================
# 14. Run Ansible provisioning
# ============================================================

log "13. Running Ansible provisioning"

ansible-playbook playbooks/site.yml

success "Ansible provisioning completed"

# ============================================================
# 15. Reset Ansible connection
# ============================================================

log "14. Resetting Ansible SSH connection"

ansible kubernetes -m meta -a reset_connection

success "Ansible connection reset"

# ============================================================
# 16. Verify containerd
# ============================================================

log "15. Verifying containerd"

ansible kubernetes -a "containerd --version"

ansible kubernetes -a "systemctl is-active containerd"

success "Containerd verified"

# ============================================================
# 17. Verify Kubernetes tools
# ============================================================

log "16. Verifying Kubernetes tools"

ansible kubernetes -a "kubeadm version"

ansible kubernetes -a "kubelet --version"

ansible kubernetes -a "kubectl version --client"

success "Kubernetes tools verified"

# ============================================================
# 18. Initialize Kubernetes cluster
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
# 19. Configure kubeconfig on EC2
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
# 20. Install Calico
# ============================================================

log "19. Installing Calico"

ansible kubernetes -b -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config apply -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml"

success "Calico installed"

# ============================================================
# 21. Remove control-plane taint
# ============================================================

log "20. Configuring single-node Kubernetes"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config taint nodes --all node-role.kubernetes.io/control-plane-" \
    || true

success "Single-node Kubernetes configured"

# ============================================================
# 22. Wait for Kubernetes node
# ============================================================

log "21. Waiting for Kubernetes node"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config wait --for=condition=Ready node --all --timeout=300s"

success "Kubernetes node is Ready"

# ============================================================
# 23. Show cluster
# ============================================================

log "22. Checking Kubernetes cluster"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config get nodes -o wide"

ansible kubernetes -a \
    "kubectl --kubeconfig=/home/ubuntu/.kube/config get pods -A"

success "Kubernetes cluster verified"

# ============================================================
# 24. Copy kubeconfig from EC2
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
# 25. Configure local kubeconfig
# ============================================================

log "24. Configuring local kubeconfig"

sed -i '/certificate-authority-data:/d' "$KUBECONFIG_FILE"

sed -i '/certificate-authority:/d' "$KUBECONFIG_FILE"

sed -i "s|^[[:space:]]*server:.*|    server: https://$INSTANCE_PUBLIC_IP:6443|" "$KUBECONFIG_FILE"

sed -i '/insecure-skip-tls-verify:/d' "$KUBECONFIG_FILE"

sed -i "/server: https:\/\/$INSTANCE_PUBLIC_IP:6443/a\\    insecure-skip-tls-verify: true" "$KUBECONFIG_FILE"

echo
echo "Kubernetes cluster configuration:"
echo "------------------------------------------------------------"

grep -A5 "server: https://$INSTANCE_PUBLIC_IP:6443" \
    "$KUBECONFIG_FILE" || true

echo "------------------------------------------------------------"

success "Kubeconfig configured"

# ============================================================
# 26. Configure local kubectl
# ============================================================

log "25. Configuring local kubectl"

mkdir -p "$HOME/.kube"

cp "$KUBECONFIG_FILE" "$HOME/.kube/config"

chmod 600 "$HOME/.kube/config"

unset KUBECONFIG

success "Local kubeconfig installed"

# ============================================================
# 27. Test kubectl
# ============================================================

log "26. Testing Kubernetes connection"

kubectl get nodes -o wide

success "kubectl successfully connected to Kubernetes"

# ============================================================
# 28. Create namespace
# ============================================================

log "27. Creating RMS namespace"

kubectl create namespace "$K8S_NAMESPACE" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "RMS namespace ready"

# ============================================================
# 29. Collect deployment secrets
# ============================================================

log "28. Collecting deployment secrets"

echo
echo "============================================================"
echo "              DATABASE CONFIGURATION"
echo "============================================================"
echo

read -rp "PostgreSQL database name [rms_db]: " POSTGRES_DB
POSTGRES_DB="${POSTGRES_DB:-rms_db}"

read -rp "PostgreSQL username [admin]: " POSTGRES_USER
POSTGRES_USER="${POSTGRES_USER:-admin}"

read -rsp "PostgreSQL password [rmspass]: " POSTGRES_PASSWORD
echo

if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD="rmspass"
fi

echo
echo "============================================================"
echo "              DJANGO CONFIGURATION"
echo "============================================================"
echo

read -rsp "Django SECRET_KEY: " SECRET_KEY
echo

[ -n "$SECRET_KEY" ] || error "Django SECRET_KEY cannot be empty."

echo
echo "============================================================"
echo "              EMAIL CONFIGURATION"
echo "============================================================"
echo

read -rp "Email host user [dev.brain08@gmail.com]: " EMAIL_HOST_USER
EMAIL_HOST_USER="${EMAIL_HOST_USER:-dev.brain08@gmail.com}"

read -rsp "Email app password: " EMAIL_HOST_PASSWORD
echo

[ -n "$EMAIL_HOST_PASSWORD" ] \
    || error "Email password cannot be empty."

echo
echo "============================================================"
echo "              GOOGLE OAUTH CONFIGURATION"
echo "============================================================"
echo

read -rp "Google Client ID: " GOOGLE_CLIENT_ID

[ -n "$GOOGLE_CLIENT_ID" ] \
    || error "Google Client ID cannot be empty."

read -rsp "Google Client Secret: " GOOGLE_SECRET
echo

[ -n "$GOOGLE_SECRET" ] \
    || error "Google Client Secret cannot be empty."

echo
echo "============================================================"
echo "              TWILIO CONFIGURATION"
echo "============================================================"
echo

read -rp "Twilio Account SID: " TWILIO_ACCOUNT_SID

read -rsp "Twilio Auth Token: " TWILIO_AUTH_TOKEN
echo

read -rp "Twilio Phone Number [+1234567890]: " TWILIO_PHONE_NUMBER
TWILIO_PHONE_NUMBER="${TWILIO_PHONE_NUMBER:-+1234567890}"

echo
echo "============================================================"
echo "              DJANGO SUPERUSER"
echo "============================================================"
echo

read -rp "Superuser username [admin]: " SUPERUSER_USERNAME
SUPERUSER_USERNAME="${SUPERUSER_USERNAME:-admin}"

read -rp "Superuser email [admin1@gmail.com]: " SUPERUSER_EMAIL
SUPERUSER_EMAIL="${SUPERUSER_EMAIL:-admin1@gmail.com}"

read -rsp "Superuser password: " SUPERUSER_PASSWORD
echo

[ -n "$SUPERUSER_PASSWORD" ] \
    || error "Superuser password cannot be empty."

success "Deployment credentials collected"

# ============================================================
# 30. Build DATABASE_URL
# ============================================================

log "29. Building database connection"

DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"

echo
echo "Database:"
echo "  $POSTGRES_DB"

echo
echo "Database user:"
echo "  $POSTGRES_USER"

echo
echo "Database host:"
echo "  postgres"

echo
echo "Database port:"
echo "  5432"

success "DATABASE_URL constructed"

# ============================================================
# 31. Create PostgreSQL Secret
# ============================================================

log "30. Creating PostgreSQL Kubernetes Secret"

kubectl create secret generic postgres-secret \
    -n "$K8S_NAMESPACE" \
    --from-literal="POSTGRES_DB=$POSTGRES_DB" \
    --from-literal="POSTGRES_USER=$POSTGRES_USER" \
    --from-literal="POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "PostgreSQL Secret created/updated"

# ============================================================
# 32. Create RMS Secret
# ============================================================

log "31. Creating RMS Kubernetes Secret"

kubectl create secret generic rms-secret \
    -n "$K8S_NAMESPACE" \
    --from-literal="SECRET_KEY=$SECRET_KEY" \
    --from-literal="DATABASE_URL=$DATABASE_URL" \
    --from-literal="EMAIL_HOST_PASSWORD=$EMAIL_HOST_PASSWORD" \
    --from-literal="GOOGLE_SECRET=$GOOGLE_SECRET" \
    --from-literal="TWILIO_ACCOUNT_SID=$TWILIO_ACCOUNT_SID" \
    --from-literal="TWILIO_AUTH_TOKEN=$TWILIO_AUTH_TOKEN" \
    --from-literal="SUPERUSER_USERNAME=$SUPERUSER_USERNAME" \
    --from-literal="SUPERUSER_EMAIL=$SUPERUSER_EMAIL" \
    --from-literal="SUPERUSER_PASSWORD=$SUPERUSER_PASSWORD" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "RMS Secret created/updated"

# ============================================================
# 33. Verify Secret names only
# ============================================================

log "32. Verifying Kubernetes Secrets"

kubectl get secret \
    postgres-secret \
    rms-secret \
    -n "$K8S_NAMESPACE"

echo
echo "Secret values are not displayed."

success "Kubernetes Secrets verified"

# ============================================================
# 34. Validate public Kubernetes manifests
# ============================================================

log "33. Validating Kubernetes manifests"

cd "$KUBERNETES_DIR"

kubectl apply \
    --dry-run=client \
    -f namespace.yaml

kubectl apply \
    --dry-run=client \
    -f configmap.yaml

kubectl apply \
    --dry-run=client \
    -f postgres-pv.yaml

kubectl apply \
    --dry-run=client \
    -f postgres-pvc.yaml

kubectl apply \
    --dry-run=client \
    -f postgres-deployment.yaml

kubectl apply \
    --dry-run=client \
    -f postgres-service.yaml

kubectl apply \
    --dry-run=client \
    -f django-deployment.yaml

kubectl apply \
    --dry-run=client \
    -f django-service.yaml

success "Kubernetes manifests validated"

# ============================================================
# 35. Deploy Kubernetes resources
# ============================================================

log "34. Deploying Rent Management System"

kubectl apply -f namespace.yaml

kubectl apply -f configmap.yaml

kubectl apply -f postgres-pv.yaml

kubectl apply -f postgres-pvc.yaml

kubectl apply -f postgres-deployment.yaml

kubectl apply -f postgres-service.yaml

kubectl apply -f django-deployment.yaml

kubectl apply -f django-service.yaml

success "RMS Kubernetes resources applied"

# ============================================================
# 36. Show RMS pods
# ============================================================

log "35. Checking RMS pods"

kubectl get pods \
    -n "$K8S_NAMESPACE" \
    -o wide

success "RMS pods created"

# ============================================================
# 37. Wait for PostgreSQL
# ============================================================

log "36. Waiting for PostgreSQL"

kubectl wait \
    --for=condition=Ready \
    pod \
    -l app=postgres \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "PostgreSQL pod is Ready"

# ============================================================
# 38. Verify PostgreSQL connectivity
# ============================================================

log "37. Verifying PostgreSQL connectivity"

POSTGRES_READY=false

for i in {1..30}; do

    echo "PostgreSQL readiness check $i/30..."

    if kubectl exec \
        -n "$K8S_NAMESPACE" \
        deployment/postgres \
        -- pg_isready \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
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
# 39. Wait for RMS deployment
# ============================================================

log "38. Waiting for RMS deployment"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "RMS rollout successful"

# ============================================================
# 40. Check RMS environment
# ============================================================

log "39. Checking RMS environment"

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
    -- printenv ALLOWED_HOSTS || true

success "RMS environment checked"

# ============================================================
# 41. Current EC2 host
# ============================================================

log "40. Verifying current EC2 host"

echo
echo "Current EC2 public IP:"
echo "  $INSTANCE_PUBLIC_IP"

success "Current EC2 host identified"

# ============================================================
# 42. Verify database connectivity
# ============================================================

log "41. Verifying RMS database connectivity"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py check --database default

success "RMS database connection verified"

# ============================================================
# 43. Run migrations
# ============================================================

log "42. Running Django migrations"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py migrate --noinput

success "Django migrations completed"

# ============================================================
# 44. Restart RMS after migrations
# ============================================================

log "43. Restarting RMS"

kubectl rollout restart \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "RMS restarted"

# ============================================================
# 45. Detect NodePort
# ============================================================

log "44. Detecting NodePort"

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
# 46. Configure dynamic Django hosts
# ============================================================

log "45. Configuring dynamic Django hosts"

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

# ============================================================
# 47. Update ConfigMap
# ============================================================

log "46. Updating RMS ConfigMap"

kubectl create configmap rms-config \
    -n "$K8S_NAMESPACE" \
    --from-literal="ALLOWED_HOSTS=$ALLOWED_HOSTS_VALUE" \
    --from-literal="CSRF_TRUSTED_ORIGINS=$CSRF_TRUSTED_ORIGINS_VALUE" \
    --from-literal="DEBUG=False" \
    --from-literal="DJANGO_ALLOWED_HOSTS=$INSTANCE_PUBLIC_IP localhost 127.0.0.1" \
    --from-literal="EMAIL_HOST_USER=$EMAIL_HOST_USER" \
    --from-literal="GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID" \
    --from-literal="TWILIO_PHONE_NUMBER=$TWILIO_PHONE_NUMBER" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "Dynamic Django configuration applied"

# ============================================================
# 48. Restart RMS with updated ConfigMap
# ============================================================

log "47. Restarting RMS with updated environment"

kubectl rollout restart \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE"

kubectl rollout status \
    deployment/"$K8S_DEPLOYMENT" \
    -n "$K8S_NAMESPACE" \
    --timeout=300s

success "RMS restarted with updated Django configuration"

# ============================================================
# 49. Verify Django environment
# ============================================================

log "48. Verifying Django environment"

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
# 50. Verify database again
# ============================================================

log "49. Verifying RMS database connectivity"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py check --database default

success "RMS database connection verified"

# ============================================================
# 51. Run migrations again
# ============================================================

log "50. Running Django migrations"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py migrate --noinput

success "Django migrations completed"

# ============================================================
# 52. Create default superuser
# ============================================================

log "51. Creating default Django superuser"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py create_superuser_default

success "Default Django superuser created/verified"
# ============================================================
# 53. Load sample data
# ============================================================

log "52. Loading sample data"

kubectl exec \
    -n "$K8S_NAMESPACE" \
    deployment/"$K8S_DEPLOYMENT" \
    -- python manage.py load_sample_data

success "Sample data loaded successfully"

# ============================================================
# 54. Check endpoints
# ============================================================

log "53. Checking RMS endpoints"

kubectl get endpoints \
    "$K8S_SERVICE" \
    -n "$K8S_NAMESPACE"

# ============================================================
# 55. Final Kubernetes status
# ============================================================

log "54. Final Kubernetes status"

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
# 56. Test RMS application
# ============================================================

log "55. Testing RMS application"

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
# 57. Final result
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
# 58. Live RMS application logs
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