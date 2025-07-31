#!/bin/bash

set -e

USER_NAME=$1
NAMESPACE=$2

if [[ -z "$USER_NAME" || -z "$NAMESPACE" ]]; then
  echo "Usage: $0 <username> <namespace>"
  exit 1
fi

USER_HOME="/home/$USER_NAME"
CERT_DIR="$USER_HOME/.certs"
KUBECONFIG_DIR="$USER_HOME/.kube"
KEY_FILE="$CERT_DIR/$USER_NAME.key"
CSR_FILE="$CERT_DIR/$USER_NAME.csr"
CRT_FILE="$CERT_DIR/$USER_NAME.crt"
CA_FILE="/var/lib/rancher/k3s/server/tls/client-ca.crt"
CA_KEY="/var/lib/rancher/k3s/server/tls/client-ca.key"

# Create cert directory
sudo mkdir -p "$CERT_DIR"
sudo chmod 700 "$CERT_DIR"
sudo chown "$USER_NAME:$USER_NAME" "$CERT_DIR"

# Generate private key
sudo openssl genrsa -out "$KEY_FILE" 2048

# Generate CSR
sudo openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -subj "/CN=$USER_NAME/O=$USER_NAME"

# Create extfile
EXTFILE=$(mktemp)
echo "extendedKeyUsage = clientAuth" > "$EXTFILE"

# Sign the CSR
sudo openssl x509 -req \
  -in "$CSR_FILE" \
  -CA "$CA_FILE" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$CRT_FILE" \
  -days 365 \
  -extfile "$EXTFILE" \
  -sha256

rm "$EXTFILE"

# Permissions
sudo chown "$USER_NAME:$USER_NAME" "$CERT_DIR"/*
sudo chmod 600 "$KEY_FILE"
sudo chmod 644 "$CRT_FILE"

echo "[+] Certificate and key generated for user '$USER_NAME'"

