#!/usr/bin/env bash
# Build the three .NET images for linux/amd64 and (optionally) push to Docker Hub.
# Usage: ./scripts/build-push.sh            # build only
#        ./scripts/build-push.sh --push     # build + push (run `docker login` first)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-alboner/plurasight-project}"
PUSH=false; [[ "${1:-}" == "--push" ]] && PUSH=true

declare -A SERVICES=(
  [catalog-api]=src/Catalog.API/Dockerfile
  [basket-api]=src/Basket.API/Dockerfile
  [service-worker]=src/ServiceWorker/Dockerfile
)

for tag in "${!SERVICES[@]}"; do
  echo "==> Building $REPO:$tag"
  docker build --platform linux/amd64 -f "${SERVICES[$tag]}" -t "$REPO:$tag" src
  if $PUSH; then
    echo "==> Pushing $REPO:$tag"
    docker push "$REPO:$tag"
  fi
done
echo "Done."
