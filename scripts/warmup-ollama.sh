#!/usr/bin/env zsh
# warmup-ollama.sh — Pre-warm Ollama models before demo

echo "Warming up Ollama models..."
echo ""

models=(
  "qwen2.5:7b"
  "qwen3-coder:30b"
  "llama3.2:3b"
)

for model in $models; do
  echo "==> Warming up $model..."
  curl -s http://localhost:11434/api/generate \
    -d "{\"model\":\"$model\",\"prompt\":\"hello\",\"stream\":false}" \
    | jq --arg model "$model" -r '"  [\($model)] response: \(.response[:50])..."'
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