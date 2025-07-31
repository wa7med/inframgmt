#!/bin/bash

# Base directory where user certs will be stored
BASE_DIR="/home"
CERT_DIR_NAME=".certs"
KUBECONFIG_DIR_NAME=".kube"
CLUSTER_NAME="k3s-cluster"
API_SERVER="https://127.0.0.1:6443"
CA_CERT="/etc/rancher/k3s/ssl/ca.crt"
CA_KEY="/etc/rancher/k3s/ssl/ca.key"

# List of users and their namespaces (same name as user)
USERS=("u_horus" "u_sphinx" "u_auto" "u_perform" "u_e2e" "u_devops" "u_shared")

for USER in "${USERS[@]}"; do
    USER_HOME="${BASE_DIR}/${USER}"
    CERT_DIR="${USER_HOME}/${CERT_DIR_NAME}"
    KUBECONFIG_DIR="${USER_HOME}/${KUBECONFIG_DIR_NAME}"
    USER_KEY="${CERT_DIR}/${USER}.pem"
    USER_CSR="${CERT_DIR}/${USER}.csr"
    USER_CRT="${CERT_DIR}/${USER}.crt"
    KUBECONFIG="${KUBECONFIG_DIR}/config"
    USER_NAMESPACE="${USER}"

    echo "==> Setting up certs and kubeconfig for ${USER}"

    # Create directories
    mkdir -p "${CERT_DIR}" "${KUBECONFIG_DIR}"
    chown -R ${USER}:${USER} "${CERT_DIR}" "${KUBECONFIG_DIR}"
    chmod 700 "${KUBECONFIG_DIR}"

    # Generate private key
    openssl genrsa -out "${USER_KEY}" 2048

    # Generate CSR
    openssl req -new -key "${USER_KEY}" -out "${USER_CSR}" -subj "/CN=${USER}/O=${USER_NAMESPACE}"

    # Sign the certificate with the cluster CA
    openssl x509 -req -in "${USER_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" \
        -CAcreateserial -out "${USER_CRT}" -days 365

    # Set permissions
    chown ${USER}:${USER} "${USER_KEY}" "${USER_CSR}" "${USER_CRT}"
    chmod 600 "${USER_KEY}" "${USER_CRT}"

    # Create kubeconfig file
    kubectl config --kubeconfig="${KUBECONFIG}" set-cluster "${CLUSTER_NAME}" \
        --server="${API_SERVER}" --certificate-authority="${CA_CERT}" --embed-certs=true

    kubectl config --kubeconfig="${KUBECONFIG}" set-credentials "${USER}" \
        --client-certificate="${USER_CRT}" --client-key="${USER_KEY}" --embed-certs=true

    kubectl config --kubeconfig="${KUBECONFIG}" set-context "${USER}-context" \
        --cluster="${CLUSTER_NAME}" --namespace="${USER_NAMESPACE}" --user="${USER}"

    kubectl config --kubeconfig="${KUBECONFIG}" use-context "${USER}-context"

    # Final ownership and permissions
    chown -R ${USER}:${USER} "${KUBECONFIG}"
    chmod 600 "${KUBECONFIG}"

    echo "✅ Completed for ${USER}"
done

echo "🎉 All user kubeconfigs and certificates are ready!"

