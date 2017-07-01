#!/usr/bin/env bash
set -euo pipefail

LATEST_STABLE=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)

curl -LO https://storage.googleapis.com/kubernetes-release/release/${LATEST_STABLE}/bin/linux/amd64/kubectl

chmod +x kubectl

./kubectl create -f .output -o yaml
