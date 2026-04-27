#!/usr/bin/env zsh
# warmup-ollama.sh — Pre-warm Ollama models before demo
# First call on large models takes 30-60s while Ollama loads into memory.
# Run this before the demo to avoid cold-start delays.

echo "Warming up Ollama models..."
echo ""

models=(
  "qwen2.5:7b"
  "qwen3-coder:30b"
)

for model in $models; do
  echo "==> Warming up $model..."
  curl -s http://localhost:11434/api/generate \
    -d "{\"model\":\"$model\",\"prompt\":\"hello\",\"stream\":false}" \
    | jq -r '"  [\($model)] response: \(.response[:50])..."'
  echo ""
done

echo "All models warmed up and ready."
echo ""
echo "Available via Bifrost:"
echo "  openai/qwen2.5:7b       — fast (~2s)"
echo "  openai/qwen3-coder:30b  — best quality (~18s)"
echo "  openai/llama3.2:3b      — very fast (~1s)"
echo "  openai/qwen2.5-coder:7b — code/k8s tasks"
echo "  openai/gemma4:latest    — general purpose"
