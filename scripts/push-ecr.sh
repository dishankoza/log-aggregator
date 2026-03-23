#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
REGISTRY="341360363145.dkr.ecr.us-west-2.amazonaws.com"
TAG="${1:-latest}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

echo "logging into ECR registry ${REGISTRY}"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

build_and_push() {
  local image_name="$1"
  local context_dir="$2"
  local repo_url="$3"

  echo "building ${image_name} from ${context_dir}"
  docker build -t "${image_name}:${TAG}" "${context_dir}"
  docker tag "${image_name}:${TAG}" "${repo_url}:${TAG}"
  echo "pushing ${repo_url}:${TAG}"
  docker push "${repo_url}:${TAG}"
}

build_consumer_and_push() {
  local repo_url="$1"

  docker tag "consumer:${TAG}" "${repo_url}:${TAG}"
  echo "pushing ${repo_url}:${TAG}"
  docker push "${repo_url}:${TAG}"
}

build_and_push "go-service" "./go-service" "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/go-service"
build_and_push "java-service" "./java-service" "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/java-service"
build_and_push "cpp-service" "./cpp-service" "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/cpp-service"
build_and_push "ui-api" "./ui-api" "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/ui-api"
build_and_push "ollama" "./ollama" "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/ollama"
build_and_push "otel-collector" "./otel-collector" "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/otel-collector"

echo "building shared consumer image"
docker build -t "consumer:${TAG}" "./consumer"
build_consumer_and_push "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/cassandra-store"
build_consumer_and_push "341360363145.dkr.ecr.us-west-2.amazonaws.com/log-aggregator/elasticsearch-indexer"

echo "all images pushed with tag ${TAG}"
