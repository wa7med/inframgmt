#!/bin/bash

set -e

# List of users
USERS=("u_sphinx" "u_auto" "u_perform" "u_e2e" "u_devops" "u_shared")

# K3s settings
K3S_CA="/var/lib/rancher/k3s/server/tls/client-ca.crt"
K3S_SERVER="https://127.0.0.1:6443"

for USER in "${USERS[@]}"; do
    HOME_DIR="/home/$USER"
    CERT_DIR="$HOME_DIR/.certs"
    KUBECONFIG_DIR="$HOME_DIR/.kube"
    KUBECONFIG_FILE="$KUBECONFIG_DIR/config"
    USER_KEY="$CERT_DIR/${USER}.key"
    USER_CRT="$CERT_DIR/${USER}.crt"
    USER_PEM="$CERT_DIR/${USER}.pem"
    USER_CA="$CERT_DIR/ca.crt"

    echo "==> Setting up $USER"

    # Create dirs
    mkdir -p "$CERT_DIR" "$KUBECONFIG_DIR"
    chmod 700 "$CERT_DIR" "$KUBECONFIG_DIR"
    chown -R "$USER:$USER" "$CERT_DIR" "$KUBECONFIG_DIR"

    # Generate private key
    openssl genrsa -out "$USER_KEY" 2048
    openssl rsa -in "$USER_KEY" -out "$USER_PEM"

    # Generate self-signed cert
    openssl req -new -key "$USER_KEY" -x509 -days 365 \
        -out "$USER_CRT" \
        -subj "/CN=$USER/O=$USER"

    # Copy CA cert
    cp "$K3S_CA" "$USER_CA"
    chmod 644 "$USER_CA"
    chown "$USER:$USER" "$USER_CA"

    # Create kubeconfig
    cat > "$KUBECONFIG_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: k3s-cluster
  cluster:
    certificate-authority: $USER_CA
    server: $K3S_SERVER
contexts:
- name: $USER-context
  context:
    cluster: k3s-cluster
    user: $USER
current-context: $USER-context
users:
- name: $USER
  user:
    client-certificate: $USER_CRT
    client-key: $USER_PEM
EOF

    chown "$USER:$USER" "$KUBECONFIG_FILE"
    chmod 600 "$KUBECONFIG_FILE"

    echo "✅ $USER is ready"
done

