#!/usr/bin/env bash
# Discover what the Pluralsight sandbox actually allows, then write scripts/.sandbox.resolved.env
# (resource group, location, usable VM sizes, node count) for create-aks.sh.
# Read-only: it only runs `az ... show/list` commands (plus a best-effort provider registration).
#
# Prerequisite: `az login` with the sandbox credentials.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/sandbox.env
OUT=scripts/.sandbox.resolved.env

info() { printf '\n==> %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }

info "1. Login and subscription"
az account show >/dev/null 2>&1 || die "Not logged in. Run: az login"
az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null \
  || die "Subscription $SUBSCRIPTION_ID not visible to this login. Run: az account list -o table"
az account show --query "{name:name,id:id,user:user.name,tenant:tenantId}" -o table

info "2. Resource group"
RG=$(az group list --query "[?name=='$RG_NAME'].name | [0]" -o tsv)
[[ -z "$RG" ]] && RG=$(az group list --query "[?contains(name,'$RG_MATCH')].name | [0]" -o tsv)
if [[ -z "$RG" ]]; then
  az group list -o table
  die "No resource group matching '$RG_NAME' / '$RG_MATCH'. Fix RG_NAME in scripts/sandbox.env."
fi
LOCATION=$(az group show -n "$RG" --query location -o tsv)
echo "  resource group : $RG"
echo "  location       : $LOCATION"
echo "  existing resources:"; az resource list -g "$RG" -o table 2>&1 | sed 's/^/    /'

info "3. Resource providers (AKS needs Compute, Network, ContainerService)"
for p in Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.OperationalInsights; do
  s=$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null)
  echo "  $p: ${s:-unknown}"
  if [[ "$s" != "Registered" && "$p" != "Microsoft.OperationalInsights" ]]; then
    az provider register -n "$p" >/dev/null 2>&1 && echo "    registration requested" || warn "cannot register $p (may be blocked in the sandbox)"
  fi
done

info "4. Azure Policy assignments that may restrict regions / VM sizes / resource types"
az policy assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --query "[].{name:displayName, enforcement:enforcementMode}" -o table 2>&1 | sed 's/^/  /' || warn "cannot list policies"
az policy assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --query "[?parameters!=null].{name:displayName, params:parameters}" -o json 2>/dev/null | head -60

info "5. vCPU quota in $LOCATION"
az vm list-usage -l "$LOCATION" --query "[?contains(name.localizedValue,'Total Regional') || contains(name.localizedValue,'Standard B') || contains(name.localizedValue,'Standard DSv3') || contains(name.localizedValue,'Standard Dv3')].{quota:name.localizedValue,used:currentValue,limit:limit}" -o table
LIMIT=$(az vm list-usage -l "$LOCATION" --query "[?name.value=='cores'].limit | [0]" -o tsv)
USED=$(az vm list-usage -l "$LOCATION" --query "[?name.value=='cores'].currentValue | [0]" -o tsv)
FREE=$(( ${LIMIT:-0} - ${USED:-0} ))
echo "  free regional vCPUs: $FREE"

info "6. VM sizes available (no restrictions) in $LOCATION"
AVAILABLE=$(az vm list-skus -l "$LOCATION" --resource-type virtualMachines --query "[?length(restrictions)==\`0\`].name" -o tsv | tr -d '\r')
CANDIDATES="Standard_B2s Standard_D2s_v3 Standard_D2as_v4 Standard_D2s_v4 Standard_DS2_v2 Standard_B2ms Standard_D2s_v5 Standard_D2as_v5 Standard_D2ds_v4 Standard_F2s_v2 Standard_A2_v2"
SIZES=""
for s in $CANDIDATES; do grep -qx "$s" <<<"$AVAILABLE" && SIZES="$SIZES $s"; done
SIZES="${SIZES# }"
[[ -z "$SIZES" ]] && { echo "$AVAILABLE" | head -40; die "None of the candidate 2-vCPU sizes are available. Pick one from the list above and set NODE_SIZES manually in $OUT."; }
echo "  usable candidates (preferred first): $SIZES"

NODES=$(( FREE / 2 )); (( NODES > 2 )) && NODES=2
(( NODES < 1 )) && die "Fewer than 2 free vCPUs in $LOCATION (AKS needs at least one 2-vCPU node)."
echo "  node count that fits the quota: $NODES (of 2 wanted)"
(( NODES < 2 )) && warn "Only 1 node fits. The monitoring stack will be tight; the deploy uses lighter limits automatically when NODE_COUNT=1."

info "7. Kubernetes versions in $LOCATION"
K8S=$(az aks get-versions -l "$LOCATION" --query "values[?isDefault==\`true\`].version | [0]" -o tsv 2>/dev/null)
echo "  default AKS version: ${K8S:-unknown (CLI default will be used)}"

cat > "$OUT" <<EOF
RG="$RG"
LOCATION="$LOCATION"
NODE_SIZES="$SIZES"
NODE_COUNT="$NODES"
K8S_VERSION="${K8S}"
EOF
info "Wrote $OUT"; cat "$OUT"
echo; echo "Next: ./scripts/create-aks.sh"
