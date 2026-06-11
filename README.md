# ai-lore

The central source of truth for the company's AI logic, capabilities, and integrations. Instead of scattering prompts, system instructions, and orchestration code across isolated repositories, all shared assets live here to ensure consistency across our applications and engineering pipelines.

### 📁 Core Structure

*   **`/models`** – Foundational provider configurations (Claude, OpenAI, Codex) including default system prompts, temperature baselines, and model version pinning.
*   **`/plugins`** – Code, manifests, and integrations connecting our core models to internal dashboards and third-party enterprise tools.
*   **`/mcps`** – Model Context Protocol setups that securely bridge LLMs to local developer environments and internal company databases.
*   **`/skills`** – Our library of atomic, reusable prompt chains designed to execute specific, deterministic tasks.
*   **`/agents`** – Full autonomous agent definitions, multi-agent orchestration frameworks, and state/memory management configurations.
*   **`/hooks`** – Middleware and event-driven webhooks used to trigger automated AI workflows directly from internal system events.
*   **`/guards`** – PII scrubbing logic, input/output moderation filters, and compliance guardrails.
*   **`/evals`** – Test suites, prompt benchmarks, and regression tests used to validate updates before they hit production.
*   **`/telemetry`** – OpenTelemetry hooks, standardized logging schemas, and trace formats to audit agent reasoning loops and prompt performance.
