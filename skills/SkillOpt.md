---
name: skillopt
description: "Meta-skill that wraps every other skill invocation with the SkillOpt discipline (Yang et al., Microsoft + SJTU + Tongji + Fudan, May 2026, arXiv:2605.23904v2). Treats each skill document as the trainable external state of a frozen agent and uses bounded add/delete/replace edits, a held-out validation gate, a rejected-edit buffer, and an epoch-wise slow/meta update to improve the skill over time. Load this skill on every future skill call — whenever the agent loads any user, space, org, or built-in skill, also load skillopt and run the SkillOpt loop around the target skill's execution. Use for skill optimization, skill self-improvement, skill auditing, propose-and-test prompt evolution, controllable text-space optimization, and producing a portable best_skill.md artifact without changing model weights."
license: MIT
metadata:
  author: manny-rodriguez
  version: '1.0'
  source_paper: "SkillOpt: Executive Strategy for Self-Evolving Agent Skills (arXiv:2605.23904v2, May 2026)"
  trigger: "Load on EVERY future skill invocation as a wrapper. The user has explicitly requested this skill be invoked on every future skill call."
---

# SkillOpt — Self-Evolving Skill Wrapper

## When to Use This Skill

**Load this skill on every future skill call.** The user has explicitly requested that whenever any other skill (user, space, org, or built-in) is loaded, this skill is also loaded and run as a wrapper around it.

Also load explicitly when the user asks to:

- Optimize, improve, train, or evolve an existing skill
- Audit a skill's behavior against actual rollouts
- Propose-and-test edits to a prompt, system instruction, or skill document
- Produce a portable `best_skill.md` artifact for a given domain
- Diagnose why a skill is underperforming and apply controlled fixes

Do **not** use SkillOpt as a substitute for the target skill's domain content. SkillOpt only governs *how* edits to the target skill are proposed, gated, and accepted — the target skill still owns the domain logic.

## Core Idea (One Paragraph)

A skill is the **external state of a frozen agent**. Train it like a parameter, not a prompt: sample rollouts under the current skill, reflect on successes and failures in minibatches, propose **bounded** add/delete/replace edits under an edit-budget "learning rate," apply only edits that **strictly improve a held-out validation score**, keep rejected edits as negative feedback, and once per epoch run a **slow/meta update** that captures longer-horizon patterns into a protected field. The deployed output is a compact `best_skill.md` (≈300–2,000 tokens) that requires zero extra inference-time model calls.

The deep-learning analogy is operational, not decorative:

| DL concept           | SkillOpt analogue                       |
|----------------------|-----------------------------------------|
| parameter            | skill document                          |
| gradient direction   | trajectory-derived edit direction       |
| learning rate        | edit budget L_t                         |
| validation check     | held-out selection gate (D_sel)         |
| batch / minibatch    | rollout batch / reflection minibatch    |
| momentum             | epoch-wise slow/meta update             |
| schedule             | constant / linear / cosine / autonomous |

## How to Run the SkillOpt Loop

When a target skill `S` is loaded for a task, SkillOpt runs the following loop around it. In a single-conversation setting "training" is lightweight — usually one or two passes — but the discipline is the same.

### 1. Setup — declare the splits

Before optimizing, partition available task evidence into three splits:

- `D_tr` — training split: rollouts here generate edit evidence.
- `D_sel` — selection split: every candidate skill is scored here; only strict improvements are accepted.
- `D_test` — test split: locked until final reporting. Never used to choose edits.

If the user only provides one task, treat the first attempt as `D_tr`, hold the user's eventual acceptance criterion as `D_sel`, and skip `D_test`. State the split assignment briefly so the user can correct it.

### 2. Forward pass — rollout evidence

Execute the target skill `S_t` against `D_tr` with the frozen target model. Record:

- task metadata, messages, tool calls, observations
- command outputs, final answers, verifier feedback
- benchmark-specific context (spreadsheet previews, document references, compact execution traces)

Small batches update quickly but noisily; larger batches expose recurring patterns. Accumulation is allowed: reflect on several batches separately, then merge into one update.

### 3. Backward pass — minibatch reflection

Partition trajectories into **failures** and **successes**, then into reflection minibatches. For each minibatch, propose **structured** edits in one of two modes:

- **Patch mode** (default): atomic `add` / `delete` / `replace` operations on the target skill document.
- **Rewrite mode**: a small set of rewrite suggestions that condition a full skill rewrite.

Failure minibatches propose **missing or corrective rules**. Success minibatches **preserve** behaviors that already work. Merge hierarchically: consolidate failure-driven edits first, success-driven edits second, then combine with **priority on failure corrections**. Drop duplicates, contradictions, and example-specific suggestions.

### 4. Bounded text update — the edit budget L_t

Rank the merged edit pool by expected utility and **clip to the top `L_t` edits**. `L_t` is the textual learning rate. Schedules:

- **constant** — fixed `L` across steps. Use only for very short loops.
- **linear** — linear decay from `L_max` to `L_min`. Use when the skill is mostly correct and needs polish.
- **cosine** *(default)* — start large, decay smoothly to small consolidation steps. Use as the default schedule.
- **autonomous** — let the optimizer pick `L_t` from the merged edit pool size and historical accept rate.

Step-level edits **must not overwrite the protected slow-update field** (see §6). Keep fast local changes and slow consolidation separated.

### 5. Validation gate — propose-and-test, not self-edit

Evaluate every candidate skill `S_{t+1}` on `D_sel` with the same frozen target model and harness.

- If `score(S_{t+1}) > score(S_t)` on `D_sel` → accept as the new **current** skill.
- If it also exceeds the best score so far → it becomes `best_skill.md`.
- Otherwise → **reject**, and write the rejection into the buffer.

This gate is non-negotiable. Plausible textual diagnoses routinely hurt the actual target model; only accept what verifiably helps.

### 6. Rejected-edit buffer — negative feedback

Maintain an **epoch-local** buffer of:

- observed failure patterns from rollouts
- for each rejected step: the edits that were tried and the score drop they caused

Prepend a summarized view of this buffer to every subsequent optimizer prompt **within the same epoch** so future proposals avoid repeating failed edits and focus on unresolved failures. This is the negative-feedback signal — it adds zero deployment cost because it's optimizer-side only.

### 7. Epoch-wise slow/meta update — the momentum term

At the end of each epoch:

1. Re-sample the **same** training items under both the previous-epoch skill and the current skill.
2. Bucket the diffs into four groups: **improvements**, **regressions**, **persistent failures**, **stable successes**.
3. Have the optimizer write a concise **longitudinal guidance block** into a protected `slow-update` field of the skill (e.g. a fenced section the patch step is forbidden from touching).
4. Pass this candidate through the **same validation gate** as a step-level edit.

The **meta-skill** is optimizer-side only: it summarizes which edit patterns helped, which were rejected, and which failures persisted. It is **prepended to future optimizer prompts only** — it is **not** shipped with the deployed `best_skill.md`. This is the separation of concerns: deployed skill stays compact and portable; training benefits from the richer record.

### 8. Export — best_skill.md

Only the validation-best skill is exported. Target ≈300–2,000 tokens after 1–4 accepted edits. The deployed artifact must be **procedural, not instance-specific** — no leaked test cases, no benchmark-specific entity names beyond what is genuinely procedural.

## Operating Rules (Hard Constraints)

1. **Never apply an unbounded rewrite.** All step-level edits must respect `L_t`. Unbounded rewrites erase useful rules and overfit to local failures.
2. **Never accept an edit without the validation gate.** If `D_sel` is unavailable, you must construct one — even a single held-out task — before accepting. Otherwise the edit is *unrejected*, not *accepted*.
3. **Never use `D_test` to choose edits.** Test is reported once, at the end. Touching it invalidates the run.
4. **Never let step-level edits write into the protected slow-update field.** Only the epoch-wise slow update may write there, and only after passing the gate.
5. **Never ship the meta-skill.** Meta lives in the optimizer prompt context, not in `best_skill.md`.
6. **Never optimize across domains in a single skill.** One skill = one domain. Cross-domain reuse is handled by transfer, not by bloating one skill.
7. **State the splits and the schedule explicitly** in the first turn of every SkillOpt run, so they are auditable.

## Adapter Interface (Harness-Agnostic)

SkillOpt is harness-agnostic. To run it inside any execution mode (direct chat, Codex-style, Claude Code-style, browser harness, custom CLI), implement an adapter with four methods:

- `build_batch(split) -> tasks` — sample tasks from `D_tr`, `D_sel`, or `D_test`.
- `inject_skill(context, skill) -> context` — prepend the skill to system/developer instructions, or write it as persistent procedural memory.
- `run(task, context) -> trajectory` — execute the frozen target model in its native harness.
- `score(trajectory, task) -> r in [0, 1]` — return the native hard score or exact-match accuracy.

The same loop then works without changes for QA, spreadsheets, documents, multimodal QA, embodied environments, or agentic execution loops.

## Default Run Configuration

When the user does not specify, use:

- **Schedule:** cosine, `L_max = 4`, `L_min = 1`.
- **Mode:** patch (atomic add/delete/replace).
- **Rollout batch size:** 4 tasks (or all available, whichever is smaller).
- **Reflection minibatch size:** 2 tasks per minibatch, failures and successes separated.
- **Epochs:** 1 by default; 2 if the skill is clearly mid-quality after the first pass.
- **Target skill size:** 300–2,000 tokens.
- **Validation gate:** strict improvement (`>`, not `≥`) on `D_sel`.

## Output Format for Every SkillOpt Run

When SkillOpt wraps a skill call, the agent should report (concisely):

1. **Splits:** which tasks went to `D_tr`, `D_sel`, `D_test`.
2. **Initial score** of `S_0` on `D_sel`.
3. **Per-step:** proposed edits (after clipping to `L_t`), accept/reject decision, new `D_sel` score.
4. **Rejected-edit buffer** summary (1–3 lines) at the end of the epoch.
5. **Slow/meta update** outcome at epoch end (accepted or rejected).
6. **Final:** `D_sel` score of `best_skill.md`, optionally `D_test` score, and the exported skill artifact.

Keep the report tight — the run is the deliverable, not the trace.

## Worked Triggers (When to Fire)

- "Optimize my prompt for X" → run SkillOpt with the prompt as `S_0`.
- "Why does skill `foo` keep failing on bar?" → run one SkillOpt epoch on `foo` with bar examples as `D_tr`.
- "Train a skill for SpreadsheetBench / SearchQA / etc." → full SkillOpt run with named splits.
- Any other skill invocation in this session → SkillOpt loads alongside and stands ready to wrap the target skill if the user asks for improvement; otherwise it stays passive and lets the target skill run.

## What SkillOpt Is Not

- Not a chain-of-thought booster. It edits the skill, not the reasoning.
- Not a model fine-tuner. The target model stays frozen.
- Not a benchmark. It does not score domain quality — the adapter's `score()` does.
- Not a replacement for domain knowledge. A bad `S_0` with no domain signal cannot be optimized into a good skill from rollouts alone.

## References

- Yang et al., *SkillOpt: Executive Strategy for Self-Evolving Agent Skills*, arXiv:2605.23904v2, May 2026. See `references/skillopt-paper-summary.md` for a fuller methodology summary.
