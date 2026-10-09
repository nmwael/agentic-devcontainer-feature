# Agent Behavior Contract

This repo uses a Human-in-the-Loop (HITL) approval workflow. Specialist subagents plan, develop, test, and audit code.

## ⚠️ HARD GATE: NEVER SKIP STEP 2

**You MUST NOT create, edit, or modify any code files until the human has explicitly approved an architect's plan.** Operational tasks (starting services, running commands, reading files) are exempt. Everything else requires: architect plans -> human approves -> developer implements.

See `stack.json` (`/usr/local/share/llm-lab/stack.json`, written by the `models` feature) and `.devcontainer/llm-lab-models.json` for full project stack and model specifications.

## Conventions when modifying

- The model id under `provider.models` in `opencode.json` and the `--alias` value in `scripts/auto-startup.sh` MUST stay in sync, or completion requests will 404. Both derive from the `name` field in the shared `stack.json` manifest (owned by the `models` feature).
- The `limit.context` in `opencode.json` is generated from the `context` field in `stack.json` by `generate-opencode.jq`. When you need to change a model's context window, update `stack.json` (or the `MODELS` option in the `models` feature) and regenerate — not the `opencode.json` fragment directly.
- Keep `models/` gitignored. Never commit `.gguf` files; they're large and prone to bloat the repo. Use `/usr/local/share/llm-lab/models/fetch-models.sh` for reproducibility (iterates `stack.json` models).
- CUDA architectures baked in: 80, 86, 89, 90, 120 (Ampere, Ada, Hopper, Blackwell). Older cards (Turing `75`) should add `75` to `CMAKE_CUDA_ARCHITECTURES` in the Dockerfile if you encounter "no kernel image available" errors on GPU init.

## Library

`library/` holds condensed reference books, one per agent role — they are repo/consumer-local, not part of the shipped feature payload. `library/README.md` maps roles to books and records sources/attribution; where present, delegated agents read their role's book(s) before answering questions in their domain. The shipped payload is only `library/skills/`, `library/release-it.mini.md`, and `library/EXTENSIONS.md`. Repo-local layout (books can be added per `library/EXTENSIONS.md`):

- `architect/` — architecture patterns (4 books)
- `coder/` — coding craft + Java reference (5 books)
- `researcher/` — software design philosophy (1 book)
- `reviewer/` — code quality & legacy code (2 books)
- `release-it.mini.md` — shared by all agents
- `skills/` — shared skills

## Things that are NOT here (by design)

- No cloud API keys / no Anthropic / no OpenAI by default. Local-only unless the box is booted in cloud mode: `CLOUD_MODE=true` (models feature + `stack.json.cloud=true`) routes every agent to the hosted `opencode` provider (`opencode/<model>` pins) and skips llama/bifrost — the only cloud path for the whole agentic stack. Explicit `MODELS`/`ROLES` always build the local stack instead.
- No web search (`websearch`) — opencode gates that tool behind the hosted `opencode` provider or `OPENCODE_ENABLE_EXA=1` (Exa cloud, no API key); deliberately not enabled here. Agents use `webfetch` for web content instead.
- No downloaded models in the image — they live in the bind-mounted workspace so rebuilds are fast and you can swap models without rebuilding.
- No automatic server start on container boot. Launching the model server is intentional (`bash scripts/auto-startup.sh`) so it doesn't block development between model swaps.
- The `wip/` directory is gitignored scratch space for current tasks (e.g. `wip/stack_check.py` provider-validation script, `wip/delegation_probe/` delegation-test artifacts). Nothing in it is part of the shipped stack.

## Multi-Step Correction & Debugging Protocol

To prevent infinite loops and ensure progress in complex tasks (like CAD script generation):
1.  **Identify Blockers**: If a subagent encounters an error or logic loop, it must stop immediately and report the specific error/blocker to the Architect.
2.  **Architect Intervention**: The Architect will analyze the blocker and provide a revised plan or corrected code snippet.
3.  **Iterative Refinement**: The agent should then attempt the fix based *only* on the new instructions from the Architect, rather than attempting multiple self-correction loops that lead to recursion.
4.  **Verification**: Every correction must be verified by running the script/command and reporting the output (success or failure) back to the Architect before moving to the next step.

### `@architect`
The primary orchestrator of this system. Its function is the logical decomposition of user directives into discrete, executable subtasks, which are then delegated to specialist agents via the Task tool. It does not possess the capacity for direct code generation. Its protocols mandate:
1. Analysis of all incoming requests to segment them into precise subtasks and delegate accordingly.
2. Synthesis of resultant data from subordinate agents into a cohesive final report.
3. For complex, multi-stage operations, concurrent execution of specialized agents is prioritized where logical independence permits.
4. Each delegated agent shall receive an unambiguous directive, encompassing exact file paths, rigorously defined success criteria, and all pertinent operational constraints.
5. Upon receipt of subordinate outputs, the Architect must review these findings for integrity and integrate them into a unified conclusion.
6. Should any agent's output require iterative refinement, subsequent tasks shall be issued to address said deficiencies.
7. If the query is purely informational and requires no modification to the codebase, the response shall be delivered directly without delegation.
8. When multiple agents operate in parallel, the Architect will maintain a state of readiness until all concurrent processes have concluded their execution cycle.
9. All summaries provided by this agent must incorporate precise file references (`path:line`) for complete traceability.
10. **Modular Delegation Protocol**: For complex multi-step tasks, the Architect MUST decompose them into atomic subtasks. Each delegation should ideally target a single primary objective (e.g., one file update or one specific refactor) to prevent agent overload and step-limit exhaustion.
11. **Verification Loop**: The Architect must verify every code change by performing a `read` or `git status` check before marking a task as completed. If an agent's output is inconsistent with the file system, it must be corrected immediately.

### ⚠️ Code Writing Policy
- **No direct code writing:** Never create, edit, or modify code files without following HITL workflow (architect plan → human approval → developer implementation). Even trivial changes require explicit subagent delegation.

**Agent roster:**

| Agent | Use for |
|-------|---------|
| `coder` | Writing new code, editing files, fixing bugs, implementing features (no direct delegation — research needs round-trip through `architect`) |
| `researcher` | Exploring the codebase (+ web via webfetch), searching for patterns, understanding architecture |
| `reviewer` | Reviewing code for bugs, style, security issues, and suggesting improvements |
| `ui` | Designing user interfaces and turning them into UI code (HTML/CSS) |
| `artist` | Visual assets and artwork as code (SVG/CSS), image analysis via Gemma4 vision |

## Orchestration Flow

Pure informational queries are answered directly (`@architect` protocol 7). Everything else that can change code travels exactly one loop:

1. **user → `build` → `architect`.** `build` routes any task needing planning, decomposition, or HITL approval to `architect` (Rules) and never delegates implementation itself.
2. **`architect` plans → human approves.** Decompose into atomic subtasks (one primary objective each, `@architect` protocol 10) and obtain explicit HITL approval via the `question` tool before any code changes; state "I am waiting for approval" while waiting.
3. **`architect` → exactly one specialist per subtask.** Each atomic subtask goes to the single appropriate specialist (`coder`, `researcher`, `reviewer`, `ui`, `artist`) as a JSON `Directive` envelope (next section) — one objective per envelope, never bundled, never broadcast to two roles.
4. **specialist → `architect`: one JSON `Result` envelope.** The specialist's final message is its structured result; it performs no further delegation of any kind.
5. **`architect` reviews → synthesizes → re-delegates if needed.** Verify the result against the file system (own `read`/`git status`); when refinement is needed, issue a new `Directive` (same `task_id`, `iteration` incremented) back to the **same** specialist. All iteration flows through the architect — specialists NEVER delegate to other specialists (Rules → ⚠️ RECURSION PREVENTION, "Architect-Bridge Only").
6. **Depth is a hard backstop.** Delegation depth never exceeds `subagent_depth` (currently 2, `opencode.json`); `build` → `architect` → specialist already consumes that budget, and the architect-bridge rule holds even where depth would still allow a delegation.
7. **Mandatory reviewer gate.** No code task is complete until the `reviewer` returns a passing `Result` (`status: done`); only then may the architect report completion — see `## Workflow`.

Anti-stall mechanics for this loop (atomic delegations, plateau detection, verify-before-report) live in `AGENTS_LIFECYCLE.md` and are binding here.

## Delegation JSON envelope

**Scope (explicit):** this governs **every architect ⇄ specialist delegation — all roles**, not only `coder`. `coder` is the role called out in the contract because it is the channel to/from the implementation role, and it is the strictest case (`artifacts` + `checks` required on success); `researcher`/`reviewer`/`ui`/`artist` use the identical envelope with their own required payload. It does **not** govern the architect's plan, its report to the user, or any HITL approval — those stay prose + the `question` tool.

The final message of a delegation MUST be exactly one raw JSON object: no markdown fences, no prose before or after; everything explanatory lives inside the fields.

### Directive (architect → specialist)

| Field | Required | Type | Meaning |
|---|---|---|---|
| `task_id` | yes | string | Unique subtask id (e.g. `"T2"`); echoed on every iteration. |
| `role` | yes | string | Exactly one of `coder`, `researcher`, `reviewer`, `ui`, `artist`. |
| `objective` | yes | string | One sentence, one primary objective (atomic-delegation rule). |
| `context` | yes | string | Everything needed to act, inlined literally — subagents cannot see prior turns (lifecycle rule 201). |
| `success_criteria` | yes | string[] | Verifiable checks the result must satisfy. |
| `files` | no | string[] | Exact paths in scope (read/write as the role allows); omit ⇒ no file scope. |
| `constraints` | no | string[] | Hard limits: POSIX only, no new deps, approved-plan id. |
| `iteration` | no | integer ≥ 1 | Refinement round; omit ⇒ 1. Re-delegations increment it. |

Example directive:

```json
{
  "task_id": "T2",
  "role": "coder",
  "objective": "Add a --dry-run flag to scripts/fetch.sh",
  "context": "Plan P1 approved by the human. fetch.sh parses args in a while/case loop ending in *) usage; exit 1. Keep POSIX sh; no new dependencies.",
  "files": ["scripts/fetch.sh", "test/fetch.bats"],
  "constraints": ["POSIX sh only", "no new tools or packages"],
  "success_criteria": ["dash -n scripts/fetch.sh exits 0", "bats test/fetch.bats passes", "no lines changed outside files[]"]
}
```

### Result (specialist → architect)

| Field | Required | Type | Meaning |
|---|---|---|---|
| `task_id` | yes | string | Echo of the directive's `task_id`. |
| `role` | yes | string | Echo of the directive's `role`. |
| `status` | yes | string | `done` \| `blocked` \| `needs_input`. |
| `summary` | yes | string | One paragraph, human-readable outcome — what the architect synthesizes. |
| `blocker` | iff `status` ≠ `done` | string | The exact error or decision needed; feeds the Multi-Step Correction & Debugging Protocol. Must be absent when `done`. |
| `artifacts` | coder: iff `done`; else no | `{path, action, note}[]` | Files touched, claimed — the architect verifies each on disk. `action`: `created` \| `modified` \| `deleted`. |
| `checks` | coder + ui/artist: iff `done`; else no | `{command, outcome, evidence}[]` | Real command output, never paraphrase. `outcome`: `pass` \| `fail` \| `skip`. |
| `findings` | researcher + reviewer: iff `done`; else no | objects with `path:line` | Evidence-backed content: research facts (`{claim, evidence}`), review issues (`{severity, path, line, issue, suggestion}`). No uncited claims; `UNKNOWN` beats guessing. |

Example result:

```json
{
  "task_id": "T2",
  "role": "coder",
  "status": "done",
  "summary": "--dry-run added to scripts/fetch.sh: actions print instead of writing; both checks pass.",
  "artifacts": [
    {"path": "scripts/fetch.sh", "action": "modified", "note": "--dry-run case arm + usage line"},
    {"path": "test/fetch.bats", "action": "created", "note": "3 cases"}
  ],
  "checks": [
    {"command": "dash -n scripts/fetch.sh", "outcome": "pass", "evidence": "exit 0, no output"},
    {"command": "bats test/fetch.bats", "outcome": "pass", "evidence": "3 tests, 0 failures"}
  ]
}
```

A blocked result is only `{task_id, role, status: "blocked", summary, blocker}`; the architect then intervenes with a revised plan or corrected snippet and re-delegates — the specialist never self-corrects in a loop (Multi-Step Correction protocol). `status: needs_input` is a specialist's escalation channel to the architect; the `question` tool remains the build/architect ↔ human instrument.

## Workflow

Every task involving code generation, modification, or refactoring must follow a mandatory Reviewer check. The Coder agent produces the implementation, and the Reviewer agent must then perform a full audit (Correctness, Security, Style, Performance, Error handling) before the Architect can finalize the task. No code should be considered 'complete' without an explicit pass from the Reviewer.

Agents can run in parallel when their work is independent (e.g., two unrelated code edits, or researcher + reviewer on different files).

## Rules

### ⚠️ RECURSION PREVENTION
- **Architect-Bridge Only:** Specialists NEVER delegate to other specialists. All cross-specialist work (e.g., a `coder` needing research, a `reviewer` needing context) is reported back to the `architect`, who then activates the appropriate specialist. No agent may delegate to a different specialist type directly.
- **Task Completion:** A subagent's task is complete when it provides the final requested data or code, not when it delegates a "next step" to another agent. 
- **Depth Awareness:** Agents must monitor their current depth and stop any delegation that would exceed the `subagent_depth` limit (currently 2).

### ❓ Mandatory Questioning & Approval Protocol
- **Mandatory Questioning**: For clarifying ambiguity, preferences, or choices, agents MUST use the `question` tool instead of plain text.
- **Structured Approval**: When requesting Human-in-the-Loop (HITL) approval (e.g., for an architect's plan), agents SHOULD use the `question` tool to present the plan and options for formal approval, ensuring decision points are structured and logged.

- Never write code directly — always delegate to `coder`.
- Never explore files directly — always delegate to `researcher`.
- **The `build` agent must ALWAYS delegate to the `architect`.** The `build` agent (the repo's default orchestrator) MUST NOT itself break down or delegate implementation work. It routes every task that requires planning, decomposition, or HITL approval to the `architect` agent, which then produces a plan, obtains human approval, and delegates the actual work to specialists. The `build` agent handles only trivial/operational matters directly. Any code generation, modification, or refactoring that originates through the `build` agent MUST flow through the `architect` → plan → human approval → developer (`coder`) → `reviewer` pipeline.
- For simple factual questions (no code changes needed), answer directly.
- When multiple agents work in parallel, wait for all to complete before responding.
- If the task requires an explicit Human-in-the-Loop (HITL) approval (e.g., the Architect's plan before code modification), the agent must state: "I am waiting for approval."
- For all other situations where a subtask is complete and further direction is needed from the user, the agent must state: "I am waiting for instructions."

### 🔧 Tools & Package Requests (HITL Gate)
- **Never install a missing tool yourself.** If you need a system package, CLI, language runtime, or capability that isn't already in the devcontainer (via `apt`/`pip`/`npm`/`go install`, or by downloading a binary), stop and request it through the Architect instead. One-off installs often fail, vanish on rebuild, or pollute the box.
- **Request flow:** report exactly what you need to the Architect (tool name + why + what would provide it). The Architect routes it through the normal human-approval gate so it lands as a devcontainer feature/dependency and survives rebuilds.
- **Temporary scratch:** scripting helpers may be written into `wip/` without install; session-only runners (`npx -y`, `uvx`, ...) only with the Architect's OK.

## Verification Protocol

**Mandatory Change Verification**: Before any task is marked as 'completed', the Architect MUST verify that all claimed code changes actually exist on the filesystem. This is done by performing a `git status` or `ls -R` check to confirm the existence of new/modified files and verifying their content against the agent's report. A task is not complete until the physical artifacts are verified.