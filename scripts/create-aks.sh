#!/usr/bin/env bash
# Create the AKS cluster in the pre-created sandbox resource group, using the values found by preflight.sh.
# Tries each usable VM size in order until one is accepted by the sandbox policies/quota.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/sandbox.env
[[ -f scripts/.sandbox.resolved.env ]] || { echo "Run ./scripts/preflight.sh first." >&2; exit 1; }
source scripts/.sandbox.resolved.env

az account set --subscription "$SUBSCRIPTION_ID" || exit 1

if az aks show -g "$RG" -n "$CLUSTER" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER already exists in $RG, skipping creation."
else
  created=false
  for SIZE in ${NODE_SIZES_OVERRIDE:-$NODE_SIZES}; do
    echo "==> az aks create: size=$SIZE nodes=$NODE_COUNT location=$LOCATION"
    args=(--resource-group "$RG" --name "$CLUSTER" --location "$LOCATION"
          --node-count "$NODE_COUNT" --node-vm-size "$SIZE" --nodepool-name sysnp
          --node-osdisk-size 64 --tier free --enable-managed-identity --generate-ssh-keys
          --tags "owner=$OWNER_TAG" "purpose=otel-grafana-demo")
    [[ -n "${K8S_VERSION:-}" ]] && args+=(--kubernetes-version "$K8S_VERSION")
    if az aks create "${args[@]}" 2>scripts/.aks-create.err; then created=true; break; fi
    echo "  failed with $SIZE:"; sed 's/^/    /' scripts/.aks-create.err | tail -8
  done
  $created || { echo "AKS creation failed for every size. See errors above (policy / quota / provider)." >&2; exit 1; }
fi

az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing
kubectl get nodes -o wide
