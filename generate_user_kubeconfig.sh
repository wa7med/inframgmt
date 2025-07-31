#!/bin/bash

set -e

# Configuration
K3S_CONFIG="/etc/rancher/k3s/k3s.yaml"
CLIENT_CA_KEY="/var/lib/rancher/k3s/server/tls/client-ca.key"
CLIENT_CA_CRT="/var/lib/rancher/k3s/server/tls/client-ca.crt"

EXPIRY_DAYS=365
ISSUER="ServiceNow"
OU="DevOps"

users=("u_horus" "u_sphinx" "u_auto" "u_perform" "u_e2e" "u_devops" "u_shared")

for user in "${users[@]}"; do
    namespace=$(echo "$user" | cut -d'_' -f2)
    cert_dir="/home/$user/.certs"
    kubeconfig_path="/home/$user/.kube/config"
    mkdir -p "$cert_dir" "/home/$user/.kube"

    # Generate key and CSR
    openssl genrsa -out "$cert_dir/$user.key" 2048
    openssl req -new -key "$cert_dir/$user.key" \
        -out "$cert_dir/$user.csr" \
        -subj "/CN=$user/O=$OU"

    # Sign the certificate
    openssl x509 -req -in "$cert_dir/$user.csr" \
        -CA "$CLIENT_CA_CRT" -CAkey "$CLIENT_CA_KEY" -CAcreateserial \
        -out "$cert_dir/$user.crt" -days "$EXPIRY_DAYS" -sha256 \
        -extfile <(printf "subjectAltName=DNS:$user") -extensions v3_req

    # Set file permissions
    chown -R "$user:$user" "$cert_dir"
    chmod 600 "$cert_dir/$user.key" "$cert_dir/$user.crt"

    # Create kubeconfig
    server=$(yq eval '.clusters[0].cluster.server' "$K3S_CONFIG")
    cluster_name=$(yq eval '.clusters[0].name' "$K3S_CONFIG")
    cluster_ca=$(yq eval '.clusters[0].cluster.certificate-authority-data' "$K3S_CONFIG")

    cat > "$kubeconfig_path" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $cluster_ca
    server: $server
  name: $cluster_name
contexts:
- context:
    cluster: $cluster_name
    namespace: $namespace
    user: $user
  name: $user-context
current-context: $user-context
users:
- name: $user
  user:
    client-certificate: $cert_dir/$user.crt
    client-key: $cert_dir/$user.key
EOF

    chown "$user:$user" "$kubeconfig_path"
    chmod 600 "$kubeconfig_path"

    # Create namespace and RBAC binding
    kubectl get ns "$namespace" >/dev/null 2>&1 || kubectl create ns "$namespace"

    kubectl create rolebinding "${user}-access" \
        --clusterrole=view \
        --user="$user" \
        --namespace="$namespace" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "✅ $user setup complete for namespace: $namespace"
done

