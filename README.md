# Log Aggregator

Distributed tracing demo and observability platform prototype built across Go, Java, and C++ services.

The request path is:

- `go-service` -> `java-service` -> `cpp-service`

Each service emits OpenTelemetry trace data. That telemetry flows through an OpenTelemetry Collector into Kafka, then fans out into:

- `Cassandra` for durable raw trace storage
- `Elasticsearch` for fast trace/span search

On top of that, a `ui-api` service provides:

- trace search
- trace detail lookup
- AI-assisted debugging summaries using a local model through Ollama

## Architecture

### Runtime Flow

1. User sends a request to `go-service`
2. `go-service` calls `java-service`
3. `java-service` calls `cpp-service`
4. All services export traces to `otel-collector`
5. `otel-collector` publishes trace data to Kafka
6. Kafka is consumed by:
   - `cassandra-store` -> writes raw OTLP payloads to Cassandra
   - `elasticsearch-indexer` -> writes flattened span documents to Elasticsearch
7. `ui-api` queries Elasticsearch and Cassandra
8. `ui-api` sends retrieved evidence to Ollama for summarization

### System Components

- `go-service`
  Public entrypoint. Starts the request chain and emits traces.

- `java-service`
  Middle service in the request path. Calls `cpp-service` and emits traces.

- `cpp-service`
  Final service in the request path. Emits traces.

- `otel-collector`
  Central telemetry ingestion layer. Receives OTLP data and exports to Kafka.

- `kafka`
  Streaming backbone for telemetry.

- `cassandra`
  Durable storage for raw trace events.

- `elasticsearch`
  Search and filtering layer for trace/span data.

- `cassandra-store`
  Kafka consumer that writes trace events into Cassandra.

- `elasticsearch-indexer`
  Kafka consumer that writes searchable span records into Elasticsearch.

- `ui-api`
  Backend and frontend for search, trace inspection, and AI summaries.

- `ollama`
  Local model-serving container used by `ui-api`.

## Project Layout

```text
go-service/              Go request entrypoint
java-service/            Java middle service
cpp-service/             C++ downstream service
consumer/                Kafka consumers for Cassandra and Elasticsearch
ui-api/                  FastAPI backend and frontend UI
ollama/                  Local model-serving image wrapper
otel-collector/          Collector image for AWS/ECR
terraform/               AWS infrastructure code
docker-compose.yml       Local development stack
otel-config.yml          Local collector config
scripts/push-ecr.sh      Build/tag/push images to ECR
```

## Local Development

### Prerequisites

- Docker
- Docker Compose
- optional: Ollama model capacity if you want AI summaries locally

### Start the Stack

From the repo root:

```bash
docker compose up --build
```

### Generate Trace Data

```bash
curl http://localhost:8080/
```

### Open the UI

```text
http://localhost:8000
```

The UI supports:

- searching spans via Elasticsearch
- loading raw trace events from Cassandra
- asking AI questions like:
  - `why is the request taking so long`
  - `which service is the bottleneck`
  - `show me traces related to java-service`

## AI Layer

`ui-api` does not send all raw data directly to the model.

Current flow:

1. Search Elasticsearch for relevant spans
2. Fetch supporting trace events from Cassandra
3. Build a reduced context
4. Call the model
5. Return a summary plus supporting evidence

The model is accessed through an OpenAI-compatible API. In local Docker, that is provided by `ollama`.

## AWS Deployment Model

The repository includes Terraform for a hybrid AWS layout:

- one EC2 instance for stateful components:
  - Kafka
  - Cassandra
  - Elasticsearch
  - Ollama
- ECS for stateless services:
  - `go-service`
  - `java-service`
  - `cpp-service`
  - `otel-collector`
  - `cassandra-store`
  - `elasticsearch-indexer`
  - `ui-api`
- ALB for ingress
- ECR for container images

## Terraform

Terraform code lives in [terraform/](/Users/dishankoza/Code/log-aggregator/terraform).

### What It Creates

- VPC
- public and private subnets
- NAT gateway
- security groups
- one EC2 stateful host
- one ECS cluster
- ALB
- IAM roles
- Cloud Map namespace
- CloudWatch log group
- ECR repositories
- ECS task definitions and ECS services

### Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
../.tools/terraform init
../.tools/terraform plan
../.tools/terraform apply
```

### Notes

- the stateful EC2 host bootstraps Kafka, Cassandra, Elasticsearch, and Ollama via Docker Compose
- ECS tasks expect container images to already exist in ECR
- the local Terraform binary is stored at `.tools/terraform`

## Push Images to ECR

After Terraform creates the ECR repositories, push images with:

```bash
./scripts/push-ecr.sh
```

To use a non-default tag:

```bash
./scripts/push-ecr.sh v1
```

The script:

- logs Docker into ECR
- builds local images
- tags them with the configured ECR repo URLs
- pushes them

## Useful Commands

### Local Docker Logs

```bash
docker compose logs --tail=100
docker compose logs -f ui-api
docker compose logs --tail=100 otel-collector kafka cassandra elasticsearch
```

### Kafka Topic Check

```bash
docker exec -it log-aggregator-kafka-1 /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list
```

### Cassandra Check

```bash
docker exec -it log-aggregator-cassandra-1 cqlsh
```

### Elasticsearch Check

```bash
curl http://localhost:9200/_cluster/health?pretty
```

### Ollama Check

```bash
curl http://localhost:11434/api/tags
```

## Troubleshooting

### No traces in the UI

- ensure `curl http://localhost:8080/` succeeds
- check `otel-collector` logs
- check Kafka topics
- confirm `cassandra-store` and `elasticsearch-indexer` are running

### AI answer falls back instead of using the model

- check `ollama` logs
- verify the selected model fits available memory
- verify `ui-api` can reach the model endpoint

### EC2 bootstrap failed on AWS

Check:

```bash
sudo cloud-init status --long
sudo tail -n 200 /var/log/cloud-init-output.log
```

### ECS services are not starting

Usually one of:

- image missing in ECR
- wrong environment variables
- stateful EC2 host not healthy yet
- security group connectivity issue to Kafka/Cassandra/Elasticsearch/Ollama

## Next Improvements

- better intent routing for AI questions
- trace tree reconstruction before summarization
- time-range filtering in UI and API
- CI/CD for image build and deployment
- managed AWS services instead of self-hosted stateful components

