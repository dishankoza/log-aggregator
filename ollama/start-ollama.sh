#!/bin/sh
set -eu

MODEL="${OLLAMA_MODEL:-llama3}"

ollama serve &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
}

trap cleanup INT TERM

until ollama list >/dev/null 2>&1; do
  sleep 1
done

if ! ollama list | awk 'NR>1 {print $1}' | grep -Fxq "$MODEL"; then
  echo "pulling ollama model: $MODEL"
  ollama pull "$MODEL"
else
  echo "ollama model already present: $MODEL"
fi

wait "$SERVER_PID"
