Here are curl examples for all the available kubernetes MCP tools via Bifrost:

```bash
export KEY="sk-bf-78daabea-6191-4b2c-afd9-"
export BF="http://localhost:8080/mcp"
```

**Namespaces**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-namespaces_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

**Pods — list all**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

**Pods — list in namespace**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_list_in_namespace","arguments":{"namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

**Pods — get single pod**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_get","arguments":{"name":"bad-app-86f6899b84-nbmdw","namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

**Pods — logs**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_log","arguments":{"name":"bad-app-86f6899b84-nbmdw","namespace":"goose-test","tail":50}}}' \
  | jq -r '.result.content[0].text'
```

**Pods — resource usage (top)**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_top","arguments":{"namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

**Nodes — resource usage (top)**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-nodes_top","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

**Events — list in namespace**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-events_list","arguments":{"namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

**Resources — list (any resource type)**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-resources_list","arguments":{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","namespace":"argocd"}}}' \
  | jq -r '.result.content[0].text'
```

**Resources — get single resource**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-resources_get","arguments":{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","name":"podinfo","namespace":"argocd"}}}' \
  | jq -r '.result.content[0].text'
```

**Configuration — view kubeconfig contexts**
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-configuration_view","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

**Discover all available tools** (run this first to confirm exact tool names)
```bash
curl -s -X POST $BF -H "Content-Type: application/json" -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '[.result.tools[].name]'
```