#!/bin/bash

# Inputs
user_name="{{ user_name }}"
user_password="{{ user_password }}"
namespace="{{ namespace }}"
team_name="{{ team_name }}"
issuer="{{ issuer }}"
K3S_CONFIG="/etc/rancher/k3s/k3s.yaml"
KUBECONFIG_PATH="/home/${user_name}/.kube/config"

# 1. Create user and home directory if not exists
if ! id "$user_name" &>/dev/null; then
    useradd -m "$user_name"
    echo "$user_name:$user_password" | chpasswd
fi

# 2. Create namespace if it doesn't exist
kubectl --kubeconfig=$K3S_CONFIG get ns "$namespace" &>/dev/null || \
kubectl --kubeconfig=$K3S_CONFIG create ns "$namespace"

# 3. Generate client certificate for user
CERT_DIR="/etc/kubernetes/pki/users/${user_name}"
mkdir -p "$CERT_DIR"
openssl genrsa -out "${CERT_DIR}/${user_name}.key" 2048

openssl req -new -key "${CERT_DIR}/${user_name}.key" \
    -out "${CERT_DIR}/${user_name}.csr" \
    -subj "/CN=${user_name}/O=${team_name}"

openssl x509 -req -in "${CERT_DIR}/${user_name}.csr" \
    -CA /etc/kubernetes/pki/ca.crt \
    -CAkey /etc/kubernetes/pki/ca.key \
    -CAcreateserial \
    -out "${CERT_DIR}/${user_name}.crt" \
    -days 365 -sha256 \
    -extfile <(printf "basicConstraints=CA:FALSE\nsubjectAltName=DNS:${user_name}\nissuer=${issuer}")

# 4. Create .kube directory
mkdir -p /home/${user_name}/.kube
chown ${user_name}:${user_name} /home/${user_name}/.kube

# 5. Generate kubeconfig scoped to namespace
kubectl config --kubeconfig="$KUBECONFIG_PATH" set-cluster k3s \
    --server=https://127.0.0.1:6443 \
    --certificate-authority=/etc/kubernetes/pki/ca.crt \
    --embed-certs=true

kubectl config --kubeconfig="$KUBECONFIG_PATH" set-credentials "$user_name" \
    --client-certificate="${CERT_DIR}/${user_name}.crt" \
    --client-key="${CERT_DIR}/${user_name}.key" \
    --embed-certs=true

kubectl config --kubeconfig="$KUBECONFIG_PATH" set-context ${user_name}-context \
    --cluster=k3s \
    --user="$user_name" \
    --namespace="$namespace"

kubectl config --kubeconfig="$KUBECONFIG_PATH" use-context ${user_name}-context

chown -R ${user_name}:${user_name} /home/${user_name}/.kube

# 6. Create Role and RoleBinding (namespace-scoped)
ROLE_NAME="${user_name}-role"
ROLE_BINDING_NAME="${user_name}-binding"

kubectl --kubeconfig=$K3S_CONFIG -n "$namespace" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${ROLE_NAME}
  namespace: ${namespace}
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
EOF

kubectl --kubeconfig=$K3S_CONFIG -n "$namespace" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${ROLE_BINDING_NAME}
  namespace: ${namespace}
subjects:
- kind: User
  name: ${user_name}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${ROLE_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

echo "✅ User $user_name is now restricted to namespace: $namespace"

