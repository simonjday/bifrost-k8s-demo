# AI Gateway Feature Comparison

> **Audience:** Kubernetes / Platform Architect
> **Date:** May 2026
> **Gateways:** Bifrost · LiteLLM · Portkey · Kong AI · Helicone

> ⚠️ GitHub star counts and pricing figures are point-in-time (May 2026) and change frequently. Verify before use in procurement decisions.

---

## Table of Contents

1. [Overview](#overview)
2. [Performance](#performance)
3. [Provider Coverage](#provider-coverage)
4. [Reliability](#reliability)
5. [Governance & Security](#governance--security)
6. [Observability](#observability)
7. [MCP & Agentic](#mcp--agentic)
8. [Caching](#caching)
9. [Kubernetes & Operations](#kubernetes--operations)
10. [Pricing](#pricing)
11. [Overall Scores](#overall-scores)
12. [Verdict by Use Case](#verdict-by-use-case)

---

## Overview

| | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Vendor** | Maxim AI | BerriAI | Portkey AI | Kong Inc. | Helicone AI |
| **Language** | Go | Python | TypeScript | Lua / Go | Rust |
| **Licence** | Apache 2.0 | MIT | MIT (OSS Mar 2026) | Apache 2.0 core + enterprise | Apache 2.0 |
| **GitHub stars** | ~3k | ~40k | ~11k | ~10k | ~5k |
| **Primary model** | Self-hosted binary | Self-hosted proxy | Managed SaaS + OSS | Self-hosted (existing Kong infra) | Managed SaaS + self-hosted |
| **Core strength** | Raw performance + MCP | Provider breadth | Observability + guardrails | Enterprise API governance | Observability / cost analytics |

### Rating Scale

| Rating | Meaning |
|---|---|
| ✅ Excellent | Best-in-class; no material gaps |
| 🟡 Good | Solid; minor limitations |
| 🟠 Partial | Available but limited or enterprise-gated |
| ❌ Poor / None | Not available or prohibitively limited |

---

## Performance

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Gateway latency overhead** | ✅ 11 µs mean at 5k RPS | ❌ Hundreds of µs; cascades at 2k+ RPS | 🟡 <1ms (self-reported, managed) | 🟡 Variable; NGINX-level overhead per AI request | 🟡 ~50ms (proxy hop) |
| **Max throughput (self-hosted)** | ✅ 5,000+ RPS benchmarked | ❌ Degrades/fails beyond ~500 RPS | 🟡 Managed SaaS; 99.99% SLA | ✅ 228% faster than Portkey (Kong bench) | 🟡 Rust perf; no published sustained-RPS figure |
| **Memory footprint** | ✅ ~120 MB under load | ❌ >8 GB at 2k RPS before OOM | 🟡 Managed; 122 KB binary (TS) | 🟠 Heavy; NGINX + Lua overhead | ✅ Rust; tiny footprint |
| **Streaming (SSE)** | ✅ First-class | 🟡 Supported | ✅ First-class | 🟡 Plugin-based | 🟡 Supported |

**Key finding:** Bifrost has no peer on raw latency. LiteLLM's P99 at equivalent load is 54x worse, with 9.4x lower throughput and 3x the memory footprint at sustained load. Kong performs well at scale but carries NGINX-level overhead that is overkill for AI-specific traffic patterns (low RPS, high latency per call due to token streaming).

---

## Provider Coverage

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Provider count** | 🟡 20+ providers | ✅ 100+ providers; widest coverage | ✅ 200+ LLMs; 1,600+ models | 🟡 Multi-LLM; thousands of models | 🟡 Dozens; GPT, Claude, Gemini etc. |
| **Custom / self-hosted models** | 🟡 Custom providers supported; Ollama validated | ✅ Ollama, vLLM, Sagemaker, NIM, HuggingFace | 🟡 Supported | 🟡 Supported as API proxy | 🟠 Limited; primarily cloud providers |
| **Drop-in SDK replacement** | ✅ OpenAI, Anthropic, Google GenAI SDKs | ✅ OpenAI format; all providers normalised | ✅ 2-line integration | 🟡 OpenAI-compatible layer | ✅ base_url swap only |

**Key finding:** LiteLLM and Portkey lead on provider breadth by a wide margin. Bifrost's 20+ covers the common cases (OpenAI, Anthropic, Bedrock, Vertex, Azure, Groq, Mistral, Ollama) but if you need Sagemaker, NIM, or less common providers, LiteLLM is the better choice.

---

## Reliability

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Automatic failover / fallbacks** | ✅ Per-virtual-key fallback chains | ✅ Retry + fallback with cooldowns | ✅ Retries, fallback, exponential backoff | 🟡 Plugin-based fallback | 🟡 Health-aware routing + circuit breaking |
| **HA / clustering (self-hosted)** | 🟠 Enterprise-only gossip clustering | 🟡 Redis for distributed rate tracking; Helm PDB | ✅ Managed 99.99% SLA; or enterprise VPC | ✅ Battle-hardened; full k8s HA native | 🟠 Self-hosted requires PostgreSQL + ClickHouse + Redis |
| **Weighted load balancing** | 🟡 Weighted per virtual key; adaptive LB enterprise-only | ✅ Latency, cost, random, round-robin, weighted | ✅ Latency + cost-based routing | ✅ Full plugin ecosystem | 🟡 Latency load-balancing |

**Key finding:** All gateways support basic failover. HA clustering in OSS is only reliable in LiteLLM (via Redis) and Kong (native). Bifrost's OSS tier is single-replica — cluster mode is enterprise-gated, which is a meaningful gap for production multi-replica deployments.

---

## Governance & Security

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Virtual keys / budget hierarchy** | ✅ 4-tier: org → team → user → key | ✅ Per user/team/key/tag; hard caps | 🟡 Workspace + team isolation | 🟡 Token rate limiting per consumer | 🟡 Rate limits; cost tracking per key |
| **RBAC** | 🟠 Enterprise-only | 🟠 Available; some features in beta | 🟡 Org/workspace isolation | ✅ Policy-as-code; federated org-wide | 🟠 Basic; not enterprise-grade |
| **SSO / SAML / OIDC** | 🟠 Enterprise-only (Okta, Entra) | 🟠 Enterprise-only (Okta, Google, SCIM, OIDC) | 🟡 Pro+; OIDC / SAML enterprise | ✅ OIDC plugin; Okta, Azure AD native | ❌ Not documented |
| **Vault / secret management** | 🟠 Enterprise-only | 🟠 AWS Secrets Manager; enterprise tier | ❌ Not documented | 🟡 Enterprise; HashiCorp Vault integration | ❌ Not documented |
| **Guardrails / content safety** | 🟠 Enterprise-only (Bedrock, Azure CS, Patronus) | 🟠 Basic keyword blocking only | ✅ 50+ guardrails in OSS; PII, content policies, output format | 🟡 Enterprise; PII redaction, semantic routing | ❌ Not a guardrails platform |
| **Audit logs** | 🟠 Enterprise-only; SOC2/GDPR/HIPAA/ISO27001 | 🟡 Full request logging; unlimited retention (self-hosted) | 🟡 30-day Pro; custom retention Enterprise | ✅ Comprehensive; policy-as-code enforcement | 🟡 Full request logging; unlimited if self-hosted |

**Key finding:** For regulated environments, the governance picture is similar across all OSS tiers. Bifrost, LiteLLM, and Kong all gate SAML/SSO and audit logs behind enterprise licensing. Portkey has the strongest OSS guardrails coverage (50+ since March 2026). Kong has the most mature enterprise governance — but requires existing Kong infrastructure.

> ⚠️ **Financial services note:** SAML, immutable audit logs, vault integration, and content guardrails are all enterprise-tier features across every gateway reviewed. Budget for enterprise licensing from day one if these are hard requirements.

---

## Observability

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Prometheus metrics** | ✅ Native; per-request + provider metrics | 🟡 Supported | 🟡 Via integration | ✅ Native; full Konnect analytics | 🟡 OTel-compatible |
| **OpenTelemetry / distributed tracing** | ✅ Native OTLP | 🟡 Langfuse, MLflow, Helicone integrations | ✅ Full traces; user/model/cost per step | 🟡 APM via plugins | ✅ Purpose-built observability; OTel-native |
| **Cost attribution** | 🟡 Budget hierarchy; token + cost logging | ✅ Real-time pricing lookup; USD cost per request | ✅ 400B+ tokens tracked daily; per use-case | 🟡 Showback/chargeback via Konnect metering | ✅ Core strength; cost forecasting, per-key analytics |
| **Built-in dashboard** | ✅ Built-in web UI; zero-config | 🟡 Admin UI; needs Langfuse for deep traces | ✅ Purpose-built LLM dashboard | 🟡 Konnect portal; requires Kong setup | ✅ Observability-first product; best-in-class dashboard |

**Key finding:** Helicone and Portkey are the observability leaders — purpose-built for LLM request tracing, cost forecasting, and per-team attribution. Bifrost's built-in dashboard is zero-config and sufficient for basic monitoring; for deep traces you need the Maxim AI integration (their paid product). LiteLLM requires Langfuse or similar for anything beyond basic request logging.

---

## MCP & Agentic

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **MCP gateway (client + server)** | ✅ Full client+server; /mcp endpoint; per-key tool allow-lists | 🟠 Fixed-endpoint MCP; limited security/observability | 🟡 OSS March 2026; auth, access control, identity forwarding | ✅ Enterprise MCP gateway; auto-gen from any API; OAuth | ❌ Not an MCP gateway |
| **Agent mode / autonomous tool execution** | ✅ Agent mode + Code mode (50% token reduction) | ❌ Not native | 🟠 Responses API MCP; no centralised auto-approval | 🟡 Agent-to-agent traffic support (3.14+) | ❌ Not applicable |
| **Federated / OAuth MCP auth** | 🟠 Enterprise-only; OAuth 2.0 + PKCE | ❌ Not documented | 🟡 Identity forwarding (email, team, roles) | ✅ Enterprise; centralised OAuth; auto-gen MCP from any API | ❌ Not applicable |
| **Real-user UI for local models** | 🟡 Open WebUI compatible (see demo repo) | 🟡 Open WebUI compatible | 🟡 Open WebUI compatible | 🟡 Open WebUI compatible | ❌ Not applicable |

**Key finding:** This is Bifrost's clearest OSS differentiator. It is the only gateway with governed MCP (per-key tool allow-lists, agent mode, code mode) in the free tier. Kong Enterprise has the deepest MCP governance for complex enterprise API estates but requires a commercial licence. Portkey added MCP in March 2026 but is still maturing. LiteLLM's MCP support is minimal.

---

## Caching

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Exact-match caching** | ✅ Built-in | 🟡 Redis-backed | ✅ Built-in | 🟡 Plugin-based | ✅ Up to 95% cost savings claimed |
| **Semantic caching** | 🟡 Weaviate/Qdrant/Redis/Pinecone; external store required | 🟡 Via AutoRouter + semantic-router | ✅ Embedding similarity; ~10–30ms lookup overhead | 🟡 Semantic caching plugin | 🟠 Not primary feature |

**Key finding:** Portkey has the most polished semantic caching — embedded, no external vector store required. Bifrost's semantic caching is capable but requires a separately-deployed Weaviate/Qdrant instance, adding operational surface area.

---

## Kubernetes & Operations

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Helm chart** | ✅ Official Helm chart + Terraform module | ✅ Official litellm-helm; PostgreSQL + Redis subcharts | 🟡 Official Helm charts published | ✅ Gold-standard k8s deployment; KIC native | 🟡 Docker/K8s supported; self-manage PostgreSQL + ClickHouse |
| **Air-gapped / on-prem** | 🟠 Enterprise-only; VPC + air-gapped documented | ✅ Fully self-hosted OSS; no external dependency | 🟠 Enterprise-only; VPC deployment | 🟡 Enterprise self-hosted; Kong hybrid mode | 🟡 Self-hosted option; heavy infra stack |
| **Operational complexity** | ✅ Single binary; SQLite default; near-zero config | 🟠 FastAPI + PostgreSQL + Redis + Prisma migrations | ✅ Managed SaaS option removes all infra burden | ❌ High; Lua plugins, DB, KIC, existing Kong infra assumed | 🟠 PostgreSQL + ClickHouse + Redis for self-hosted |
| **Real-user chat UI** | 🟡 Open WebUI via Docker (see demo repo) | 🟡 Open WebUI compatible | 🟡 Own managed UI | 🟡 Via Kong Developer Portal | ✅ Own observability UI |
| **Prompt management / versioning** | 🟠 Prompt repository (playground only) | ❌ No built-in prompt management | ✅ Hosted/enterprise; versioning, playground, A/B testing | 🟠 Via plugins; not a primary feature | 🟠 Experiment tracking; not full prompt mgmt |

**Key finding:** Bifrost wins on operational simplicity by a wide margin — single Go binary, SQLite default, `kubectl apply` in minutes. LiteLLM requires Redis + PostgreSQL + Prisma migrations for production-grade multi-replica operation. Helicone self-hosted adds ClickHouse to that stack. Kong assumes existing Kong infrastructure and Lua plugin expertise.

### Infrastructure requirements at a glance

| Gateway | Minimum production stack |
|---|---|
| **Bifrost** | 1 Pod, 256Mi RAM, optional PostgreSQL for persistence |
| **LiteLLM** | Pod + PostgreSQL + Redis (required for distributed rate limiting) |
| **Portkey** | SaaS: nothing. Self-hosted: PostgreSQL + managed infra |
| **Kong AI** | Kong Data Plane + Control Plane + DB (PostgreSQL) + KIC |
| **Helicone** | Pod + PostgreSQL + ClickHouse + Redis |

---

## Pricing

| Feature | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **OSS licence** | ✅ Apache 2.0; full-featured OSS core | ✅ MIT; 40k+ GitHub stars | ✅ MIT (OSS since March 2026) | 🟠 Apache 2.0 core; enterprise licence for production features | ✅ Apache 2.0; free tier 100k req/mo |
| **Managed SaaS option** | ❌ Self-hosted only | 🟠 Managed option; custom pricing | ✅ Primary product is managed SaaS; free tier | 🟡 Kong Konnect managed; enterprise pricing | ✅ Free 100k/mo; Pro $25/mo flat unlimited |
| **Enterprise price transparency** | ❌ Contact sales; no published tiers | ❌ Usage-based; contact sales | 🟡 Free → Pro (volume-based) → Enterprise (custom) | ❌ Contact sales | ✅ Free → Pro $25/mo → Enterprise custom |
| **Provider markup** | ✅ Zero; pay infra + upstream only | ✅ Zero; pay infra only | ✅ Zero markup on tokens | 🟡 Per-service licensing costs | ✅ Zero markup; flat SaaS fee only |

### Published pricing reference (May 2026)

| Gateway | OSS / Free | Paid / Pro | Enterprise |
|---|---|---|---|
| **Bifrost** | Free (self-hosted) | — | Custom (contact sales); 14-day trial |
| **LiteLLM** | Free (self-hosted) | — | Custom (contact sales; usage-based) |
| **Portkey** | Free (10k logs/mo) | Volume-based tiers | Custom; VPC deployment |
| **Kong AI** | Free (OSS core only) | Kong Konnect tiers | Custom; contact sales |
| **Helicone** | Free (100k req/mo) | $25/mo flat (unlimited requests) | Custom |

> ⚠️ **LiteLLM TCO note:** While the licence costs $0, self-hosted production deployments (Redis + PostgreSQL + ops labour) typically run $2,000–$3,500/month — more expensive than managed alternatives at under 5M requests/month.

---

## Overall Scores

Scores are derived from the feature assessments above using: ✅ = 4 pts, 🟡 = 3 pts, 🟠 = 2 pts, ❌ = 1 pt.
Percentage = (sum of points) / (max possible points for that category) × 100.

| Category | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| **Performance** | ✅ 95% | ❌ 25% | 🟡 70% | 🟡 75% | 🟡 75% |
| **Provider Coverage** | 🟡 75% | ✅ 100% | ✅ 92% | 🟡 75% | 🟠 58% |
| **Reliability** | 🟡 67% | 🟡 75% | ✅ 92% | ✅ 92% | 🟠 58% |
| **Governance & Security** | 🟠 42% | 🟠 50% | 🟡 67% | ✅ 83% | ❌ 25% |
| **Observability** | 🟡 83% | 🟡 67% | ✅ 92% | 🟡 67% | ✅ 92% |
| **MCP & Agentic** | ✅ 83% | ❌ 17% | 🟡 58% | ✅ 92% | ❌ 8% |
| **Caching** | 🟡 75% | 🟡 63% | ✅ 100% | 🟡 75% | 🟡 63% |
| **Kubernetes & Ops** | ✅ 88% | 🟠 50% | 🟡 75% | 🟠 50% | 🟠 50% |
| **Pricing** | 🟡 63% | 🟡 63% | 🟡 75% | 🟠 50% | ✅ 94% |
| **Overall** | **🟡 75%** | **🟠 51%** | **🟡 80%** | **🟡 73%** | **🟡 58%** |

---

## Verdict by Use Case

### Choose Bifrost when:

- **Performance is non-negotiable.** 11 µs overhead, 5k+ RPS, 120 MB RAM — nothing else is close in OSS.
- **You need MCP gateway governance in the free tier.** Per-key tool allow-lists, agent mode, and unified LLM + MCP control plane.
- **Operational simplicity matters.** Single binary, SQLite default — up in minutes on k3d or kind with a single `kubectl apply`.
- **You want a real-user chat UI alongside the gateway.** Open WebUI pairs cleanly with Bifrost via `OPENAI_API_BASE_URL` — see the demo repo for setup.
- **You're evaluating before a vendor conversation.** The OSS tier is genuinely production-capable for non-regulated internal workloads.
- **Watch out for:** Enterprise features (clustering, guardrails, SAML, vault) are all gated. Regulated environments will need the enterprise tier — and pricing is opaque.

### Choose LiteLLM when:

- **You need the widest possible provider coverage.** 100+ providers including Sagemaker, NIM, Hugging Face, and obscure endpoints.
- **Your team is Python-native** and wants to stay in that ecosystem.
- **You're operating at >50M requests/month** where fixed self-hosting TCO becomes cost-competitive with managed alternatives.
- **Watch out for:** Severe performance ceiling (~500 RPS before degradation). Hidden TCO (Redis + PostgreSQL + ops) of $2–3.5k/mo at production scale. RBAC/SSO enterprise-gated.

### Choose Portkey when:

- **Observability depth is the priority.** Full distributed traces — who called what, which fallback triggered, exact cost per step — out of the box.
- **You want managed SaaS** with no infra to operate, especially for teams without dedicated platform engineering.
- **Guardrails are required in OSS.** 50+ guardrail types since March 2026; best-in-class for content safety without enterprise licensing.
- **Prompt management and A/B testing** are part of the workflow.
- **Watch out for:** Log retention limits on lower tiers. Limited MCP governance maturity (March 2026 launch). Enterprise VPC deployment required for data residency.

### Choose Kong AI when:

- **Kong is already in the stack.** The AI gateway is an extension, not a new system to operate.
- **Enterprise API governance** (policy-as-code, federated org-wide, audit trails) is required across both traditional APIs and LLM traffic.
- **Deepest enterprise MCP governance** — auto-generate MCP servers from any API; centralised OAuth; Konnect portals as MCP entry points.
- **Watch out for:** High operational overhead if Kong isn't already present. Lua plugin expertise assumed. Enterprise licence required for production guardrails and PII redaction.

### Choose Helicone when:

- **You want the best cost visibility and request analytics** with minimal setup friction.
- **Pricing transparency matters** — $25/mo Pro flat for unlimited requests is the clearest value proposition in the market.
- **You're observability-first** and already have another layer handling routing and failover.
- **Watch out for:** Not a full governance or MCP platform. Pairs well with another gateway for budget enforcement and provider routing. Self-hosted stack (PostgreSQL + ClickHouse + Redis) is heavier than it appears.

---

## Financial / Regulated Environment Summary

| Requirement | Bifrost | LiteLLM | Portkey | Kong AI | Helicone |
|---|---|---|---|---|---|
| SAML/SSO | 🟠 Enterprise | 🟠 Enterprise | 🟡 Pro+ | ✅ Native | ❌ |
| Immutable audit logs | 🟠 Enterprise | 🟡 Self-hosted | 🟡 Pro+ custom | ✅ | 🟡 Self-hosted |
| Content guardrails | 🟠 Enterprise | 🟠 Basic only | ✅ OSS | 🟡 Enterprise | ❌ |
| Air-gapped deployment | 🟠 Enterprise | ✅ OSS | 🟠 Enterprise | 🟡 Enterprise | 🟡 Self-hosted |
| Vault integration | 🟠 Enterprise | 🟠 Enterprise | ❌ | 🟡 Enterprise | ❌ |
| Published ZDR policy | ❌ | ❌ | 🟡 Partial | 🟡 Partial | 🟡 Partial |

All gateways reviewed require enterprise licensing for the full compliance feature set. None publish a complete Zero Data Retention policy in their public documentation. Obtain written confirmation from vendors before procurement in regulated environments.

---

*Review compiled May 2026. Benchmark figures include vendor-published data and should be independently validated before use in procurement decisions. GitHub star counts and pricing are point-in-time and subject to change.*
