# Agent Behavior Contract

This repo uses a Human-in-the-Loop (HITL) approval workflow. Specialist subagents plan, develop, test, and audit code.

## ⚠️ HARD GATE: NEVER SKIP STEP 2

**You MUST NOT create, edit, or modify any code files until the human has explicitly approved an architect's plan.** Operational tasks (starting services, running commands, reading files) are exempt. Everything else requires: architect plans -> human approves -> developer implements.

See `library/ai-researcher/project_stack.md` for full project stack and model specifications.

Design-flow reference: [`SELF_DISCOVERING_FLOWS.md`](SELF_DISCOVERING_FLOWS.md) records the audit and agreed plan for making the boxforsine CrewAI/OpenMirai flows genuinely self-discovering (LLM proposes per-variant geometry, generator materializes, `verify_pair.py` scores, loop iterates) instead of replaying hard-coded `VARIANT_PROFILES`.

## Conventions when modifying

- The model id under `provider.models` in `opencode.json` and the `--alias` value in `serve.sh` MUST stay in sync, or completion requests will 404.
- Increase `--ctx-size` (`CTX` env) on `serve.sh` if you hit "context length exceeded" mid-session. The `limit.context` in `opencode.json` should match the value you set so opencode's context tracker is accurate.
- Keep `models/` gitignored. Never commit `.gguf` files; they're large and prone to bloat the repo. Use `scripts/fetch-model.sh` for reproducibility.
- CUDA architectures baked in: 80, 86, 89, 90, 120 (Ampere, Ada, Hopper, Blackwell). Older cards (Turing `75`) should add `75` to `CMAKE_CUDA_ARCHITECTURES` in the Dockerfile if you encounter "no kernel image available" errors on GPU init.

## Library

`library/` holds condensed reference books, one per agent role. `library/README.md` maps roles to books and records sources/attribution. Delegated agents are expected to read their role's book(s) before answering questions in their domain. Layout:

- `architect/` — architecture patterns (3 books)
- `ai-researcher/` — llama.cpp reference (original, grounded in this repo)
- `coder/` — coding craft + Java reference (4 books)
- `researcher/` — software design philosophy (1 book)
- `reviewer/` — code quality & legacy code (2 books)
- `release-it.mini.md` — shared by all agents

## Things that are NOT here (by design)

- No cloud API keys / no Anthropic / no OpenAI. Local-only.
- No web search (`websearch`) — opencode gates that tool behind the hosted `opencode` provider or `OPENCODE_ENABLE_EXA=1` (Exa cloud, no API key); deliberately not enabled here. Agents use `webfetch` for web content instead.
- No downloaded models in the image — they live in the bind-mounted workspace so rebuilds are fast and you can swap models without rebuilding.
- No automatic server start on container boot. Launching the model server is intentional (`bash scripts/serve.sh`) so it doesn't block development between model swaps.
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
| `ai-researcher` | AI research: codebase + web research, library-aware (reads its role's books) |
| `3d-designer` | Specializes in 3D printing design and STL generation |
| `ui` | Designing user interfaces and turning them into UI code (HTML/CSS) |
| `artist` | Visual assets and artwork as code (SVG/CSS), image analysis via Gemma4 vision |

## Workflow

Every task involving code generation, modification, or refactoring must follow a mandatory Reviewer check. The Coder agent produces the implementation, and the Reviewer agent must then perform a full audit (Correctness, Security, Style, Performance, Error handling) before the Architect can finalize the task. No code should be considered 'complete' without an explicit pass from the Reviewer.

For 3D design tasks, the `3d-designer` is the primary specialist for geometry generation and STL export. The workflow follows:
Researcher → Architect → [Designer/Coder] → Reviewer.

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
