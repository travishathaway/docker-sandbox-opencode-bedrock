#!/bin/bash
# Build and optionally push the thath/opencode-bedrock image.
#
# Usage:
#   ./build.sh                    # build locally for the current arch
#   ./build.sh --push             # build multi-arch and push to Docker Hub
#   ./build.sh --push --tag 1.2.3 # push and apply an additional version tag

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="thath/opencode-bedrock"
TAG="latest"
PUSH=false

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)       PUSH=true; shift ;;
        --tag)        TAG="$2"; shift 2 ;;
        --tag=*)      TAG="${1#--tag=}"; shift ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--push] [--tag VERSION]

Options:
  --push          Build multi-arch (linux/amd64 + linux/arm64) and push to Docker Hub
  --tag VERSION   Apply an additional tag alongside 'latest' (e.g. 1.2.3)

Without --push, builds a local image tagged opencode-bedrock:latest.
EOF
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo "ERROR: docker not found — install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "ERROR: Docker daemon not running — start Docker Desktop and retry"
    exit 1
fi

# ---------------------------------------------------------------------------
# Push: multi-arch via buildx
# ---------------------------------------------------------------------------
if [[ "$PUSH" == true ]]; then
    if ! docker buildx version &>/dev/null; then
        echo "ERROR: docker buildx not available (required for --push)"
        exit 1
    fi

    BUILDER="opencode-bedrock-builder"
    if ! docker buildx ls | grep -q "$BUILDER"; then
        docker buildx create --name "$BUILDER" --use
    else
        docker buildx use "$BUILDER"
    fi

    docker login

    TAGS=(-t "docker.io/$IMAGE:latest")
    [[ -n "$TAG" && "$TAG" != "latest" ]] && TAGS+=(-t "docker.io/$IMAGE:$TAG")

    echo "Building and pushing docker.io/$IMAGE (linux/amd64, linux/arm64)..."
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        "${TAGS[@]}" \
        --push \
        "$SCRIPT_DIR"

    echo ""
    echo "Pushed to Docker Hub. Pull with:"
    echo "  docker pull $IMAGE:latest"

# ---------------------------------------------------------------------------
# Local: single-arch build
# ---------------------------------------------------------------------------
else
    TAGS=(-t "opencode-bedrock:latest")
    [[ -n "$TAG" && "$TAG" != "latest" ]] && TAGS+=(-t "opencode-bedrock:$TAG")

    echo "Building opencode-bedrock:latest ($(uname -m))..."
    docker build "${TAGS[@]}" "$SCRIPT_DIR"
    echo "Done. Image tagged opencode-bedrock:latest"
fi
