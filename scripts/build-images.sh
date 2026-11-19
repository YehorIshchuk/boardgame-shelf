#!/usr/bin/env bash
# Збирає образи backend і frontend з вказаною версією та завантажує їх у minikube.
# Альтернатива публікації в GHCR через CI (git tag v1.0.0 && git push origin v1.0.0).
#
#   ./scripts/build-images.sh 1.0.0
#   ./scripts/build-images.sh 1.1.0
set -euo pipefail

VERSION="${1:?usage: $0 <version, e.g. 1.0.0>}"
REGISTRY="${REGISTRY:-ghcr.io/yehorishchuk}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$VERSION" == "latest" ]]; then
  echo "Тег latest не використовуємо — вкажіть версію, напр. 1.0.0" >&2
  exit 1
fi

for svc in backend frontend; do
  image="$REGISTRY/boardgame-shelf-$svc:$VERSION"
  echo ">>> build $image"
  docker build --build-arg APP_VERSION="$VERSION" -t "$image" "$ROOT/$svc"
  echo ">>> load $image into minikube"
  minikube image load "$image"
done

echo ">>> образи в minikube:"
minikube image ls | grep boardgame-shelf || true
