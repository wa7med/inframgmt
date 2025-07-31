#!/bin/bash

set -e

USER_NAME=$1
NAMESPACE=$2

if [[ -z "$USER_NAME" || -z "$NAMESPACE" ]]; then
  echo "Usage: $0 <username> <namespace>"
  exit 1
fi

USER_HOME="/home/$USER_NAME"
KUBECONFIG_DIR="$USER_HOME/.kube"
CONFIG_FILE="$KUBECONFIG_DIR/config"
CERT_DIR="$USER_HOME/.certs"
KEY_FILE="$CERT_DIR/$USER_NAME.key"
CRT_FILE="$CERT_DIR/$USER_NAME.crt"
CA_FILE="$CERT_DIR/ca.crt"

# Copy the CA cert
sudo cp /var/lib/rancher/k3s/server/tls/client-ca.crt "$CA_FILE"
sudo chown "$USER_NAME:$USER_NAME" "$CA_FILE"
sudo chmod 644 "$CA_FILE"

# Create .kube dir
sudo mkdir -p "$KUBECONFIG_DIR"
sudo chown "$USER_NAME:$USER_NAME" "$KUBECONFIG_DIR"
sudo chmod 700 "$KUBECONFIG_DIR"

# Generate kubeconfig
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

sudo -u "$USER_NAME" kubectl config --kubeconfig="$CONFIG_FILE" set-cluster "$CLUSTER_NAME" \
  --server="$CLUSTER_SERVER" \
  --certificate-authority="$CA_FILE" \
  --embed-certs=true

sudo -u "$USER_NAME" kubectl config --kubeconfig="$CONFIG_FILE" set-credentials "$USER_NAME" \
  --client-certificate="$CRT_FILE" \
  --client-key="$KEY_FILE" \
  --embed-certs=true

sudo -u "$USER_NAME" kubectl config --kubeconfig="$CONFIG_FILE" set-context "$USER_NAME-context" \
  --cluster="$CLUSTER_NAME" \
  --user="$USER_NAME" \
  --namespace="$NAMESPACE"

sudo -u "$USER_NAME" kubectl config --kubeconfig="$CONFIG_FILE" use-context "$USER_NAME-context"

sudo chmod 600 "$CONFIG_FILE"

echo "[+] Kubeconfig created for user '$USER_NAME'"

