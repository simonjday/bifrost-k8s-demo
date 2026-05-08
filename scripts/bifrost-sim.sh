#!/bin/bash
# bifrost-sim.sh
# Generates synthetic traffic through Bifrost to populate Prometheus metrics
# Usage: bash bifrost-sim.sh [num_requests]

KEY="sk-bf-0b7391e8-12b3-45f7-bf83-69f6f8910115"
BF="http://localhost:8080/v1/chat/completions"
REQUESTS=${1:-40}

MODELS=(
  "openai/llama3.2:3b"
  "openai/qwen2.5-coder:7b"
)

PROMPTS=(
  "What is Kubernetes in one sentence?"
  "Explain Prometheus metrics in 2 sentences."
  "What is a service mesh?"
  "Describe what an API gateway does briefly."
  "What is observability in software systems?"
  "What is a container?"
  "Explain GitOps briefly."
  "What does a load balancer do?"
  "What is PromQL?"
  "Explain the difference between logs, metrics and traces."
)

echo "Starting Bifrost traffic simulation — $REQUESTS requests across ${#MODELS[@]} models..."
echo ""

SUCCESS=0
FAIL=0

for i in $(seq 1 $REQUESTS); do
  MODEL=${MODELS[$((RANDOM % ${#MODELS[@]}))]}
  PROMPT=${PROMPTS[$((RANDOM % ${#PROMPTS[@]}))]}

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BF \
    -H "Content-Type: application/json" \
    -H "x-api-key: $KEY" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":100}")

  if [ "$STATUS" = "200" ]; then
    SUCCESS=$((SUCCESS + 1))
    echo "[$i/$REQUESTS] ✓ $MODEL → $STATUS"
  else
    FAIL=$((FAIL + 1))
    echo "[$i/$REQUESTS] ✗ $MODEL → $STATUS"
  fi

  sleep 2
done

echo ""
echo "Done — $SUCCESS succeeded, $FAIL failed"
echo "Wait ~30s for Prometheus to scrape, then check Postman 🔮 Bifrost — Gateway Metrics"
