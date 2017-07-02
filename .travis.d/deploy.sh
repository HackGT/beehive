#!/usr/bin/env bash
set -euo pipefail

install_kubectl() {
    LATEST_STABLE=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    curl -LO https://storage.googleapis.com/kubernetes-release/release/${LATEST_STABLE}/bin/linux/amd64/kubectl

    chmod +x kubectl
    mv kubectl /usr/bin/
    mkdir ~/.kube
    echo "${KUBE_CONFIG}" | base64 -d > ~/.kube/config
    hash -r
}

install_helm() {
    curl -LO 'https://kubernetes-helm.storage.googleapis.com/helm-v2.5.0-linux-amd64.tar.gz'
    tar -zxvf 'helm-v2.5.0-linux-amd64.tar.gz'
    chmod +x linux-amd64/helm
    mv linux-amd64/helm /usr/bin/
    hash -r
    helm init --client-only
    helm repo update
}

install_kubectl
install_helm

echo; echo "Checking kubectl connection!"; echo
kubectl describe services

echo; echo "Checking helm connection!"; echo
helm list

# don't do this yet!
# helm install
# kubectl create -f .output -o yaml
