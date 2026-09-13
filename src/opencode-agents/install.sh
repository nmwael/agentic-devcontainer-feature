#!/bin/sh
set -e

echo "Activating feature 'opencode-agents'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'overwrite' -> $OVERWRITE, 'with_library' -> $WITH_LIBRARY).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

OVERWRITE="${OVERWRITE:-false}"
WITH_LIBRARY="${WITH_LIBRARY:-true}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/share/opencode-agents}"

FEATURE_PAYLOAD_DIR="/usr/local/share/llm-lab/opencode-agents-payload"
mkdir -p "$FEATURE_PAYLOAD_DIR"

echo "Opencode-agents config: OVERWRITE=$OVERWRITE WITH_LIBRARY=$WITH_LIBRARY INSTALL_DIR=$INSTALL_DIR"

# Unpack payload tarball → INSTALL_DIR
# The payload is a pre-built tarball containing the agentic setup.
# For now, we create the scaffold structure from the canonical source in this repo.

# Ship AGENTS.md and AGENTS_LIFECYCLE.md
mkdir -p "$INSTALL_DIR"

# Copy AGENTS.md (the behavioral/HITL contract)
if [ ! -d "$INSTALL_DIR/.opencode" ]; then
    # Create .opencode/agent/ directory structure
    mkdir -p "$INSTALL_DIR/.opencode/agent"
fi

# Copy generic agent definitions (maintenance-free, model-slot env-templated)
    # These are the agent role definitions that make opencode behave like this repo
    cat > "$INSTALL_DIR/AGENTS.md" <<'AGENTS_MD_EOF'
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
AGENTS_MD_EOF

    # Copy AGENTS_LIFECYCLE.md
    cat > "$INSTALL_DIR/AGENTS_LIFECYCLE.md" <<'AGENTS_LIFECYCLE_MD_EOF'
# Project Lifecycle Reference

[Agent Task Lifecycle](AGENTS_LIFECYCLE.md)

# Your Agentic Workspace

This project uses a Human-in-the-Loop (HITL) approval workflow. Specialist subagents plan, develop, test, and audit code.

## ⚠️ HARD GATE: NEVER SKIP STEP 2

**You MUST NOT create, edit, or modify any code files until the human has explicitly approved an architect's plan.** Operational tasks (starting services, running commands, reading files) are exempt. Everything else requires: architect plans -> human approves -> developer implements.

See `library/ai-researcher/project_stack.md` for full project stack and model specifications.

Design-flow reference: [`SELF_DISCOVERING_FLOWS.md`](SELF_DISCOVERING_FLOWS.md) records the audit and agreed plan for making the boxforsine CrewAI/OpenMirai flows genuinely self-discovering (LLM proposes per-variant geometry, generator materializes, `verify_pair.py` scores, loop iterates) instead of replaying hard-coded `VARIANT_PROFILES`.

## ⚙️ ANTI-STALL & AGENTIC EFFICIENCY PROTOCOLS (Continuous Completion)

The Architect must never stall or abandon work mid-task. These rules override convenience and are mandatory:

1. **Atomic Delegations:** Every delegation must be small enough to complete well within the subagent's step budget (`steps` in `opencode.json`). Rule of thumb: one delegation = at most ~3 files written OR one script execution plus validation. Split larger jobs into sequential delegations.
2. **Immediate Recovery:** If any subagent returns blocked, incomplete, or step-limited, OR if the Architect detects a subagent repeating the same tool call with identical parameters/content in a loop, the Architect MUST immediately intervene — stop the execution and re-issue the work as smaller delegations. Never end the turn while planned work remains undone, unless a human decision is genuinely required.
3. **Delegation Failure Fallback:** If two consecutive delegation attempts fail or are cancelled, the Architect may perform the remaining surgical edits directly with its own tools rather than stalling — provided the human has explicitly requested the change.
4. **Verify Before Reporting:** The Architect must confirm every claimed artifact exists (via its own glob/read/bash check) before reporting success to the user. Unverified success reports are forbidden.
5. **Completion Contract:** Work is complete only when ALL agreed deliverables exist on disk and pass their checks (e.g., STL files exist AND validate). The todo list drives execution; continue until it is empty or a human decision is required.
6. **Checkpoint Notes:** For multi-session projects, maintain a progress file (e.g., `notes.md`) updated after every completed unit so interrupted work resumes losslessly.
7. **Budget Awareness:** Prefer several small reliable delegations over one large fragile one. If nearing any step limit, checkpoint progress and split the remainder.

### 🚀 AGENTIC EFFICIENCY & LOOP PREVENTION (New)

To prevent "Infinite Spins" and "Step Exhaustion," all agents must adhere to these advanced patterns:

* **Atomic Task Decomposition:** Never issue a single task that contains more than 3 logical steps. If a task involves research, implementation, and verification, it MUST be split into three separate delegations.
* **Prompt Chaining (Outline-First):** For complex code generation, the first delegation must only be to create a *pseudocode outline*. The second delegation then implements that specific outline. This prevents cognitive overload and step-limit hits.
* **Bounded Iteration & Plateau Detection:** If an agent encounters the same error twice or fails to make progress across two turns (a "plateau"), it MUST stop immediately and delegate back to the Architect for a revised plan rather than attempting a third self-correction loop.
* **Verification as Reward:** Agents should be encouraged to use tool outputs (e.g., running `pytest` or `trimesh` validation) as their own internal signal of success, rather than relying on verbal claims.
* **Artifact Isolation:** All temporary/scratch files MUST use unique UID-prefixed names (e.g., `scratch_uuid_name.py`) to prevent collisions and accidental overwrites during parallel agent runs.

## Agent communication rules (hard-learned from diagnostics)

201: - Subagents have fully isolated context: they cannot see earlier conversation turns. Never reference prior-turn content in a delegation prompt — always inline the full literal content.
202: - Never trust a subagent's success report. Verify every write with the architect's own read/glob before reporting success to the user.
203: - Prefer full-content write over surgical edit when creating or rewriting files. After any edit, re-read the file to confirm original content was preserved.
204: - Scratch/tmp files a subagent writes for itself (wip/, /tmp/opencode, or the workspace) MUST be uid-prefixed (e.g., `scratch_<flow>_<uuid4>/` or `<short-uuid>_name.py`) so concurrent agents never collide or overwrite each other's working files.
205: - The build agent AND the architect must watch delegated subagents for stuck states — repeated identical failures, self-retry loops, no progress across delegations, or step-limit exhaustion — and intervene immediately: stop the loop, re-issue a smaller delegation, or escalate to the architect for a revised plan; never let a stuck subagent burn budget in a self-correction loop.
206: - Researcher reports must back every factual claim with verbatim evidence (file:line) and must answer UNKNOWN rather than guess. A report that defers its own deliverables (e.g. ends with "next steps" or promises further reading) is a failed delegation — re-issue immediately.
207: - Before finalizing, every agent must re-read the files it cites. A cited line number that does not exist in the file, or a detail (e.g. "no trailing newline") contradicted by the actual bytes, is a failed deliverable.

## Verification Protocol

**Mandatory Change Verification**: Before any task is marked as 'completed', the Architect MUST verify that all claimed code changes actually exist on the filesystem. This is done by performing a `git status` or `ls -R` check to confirm the existence of new/modified files and verifying their content against the agent's report. A task is not complete until the physical artifacts are verified.
AGENTS_LIFECYCLE_MD_EOF

    # Copy library/EXTENSIONS.md guide
    mkdir -p "$INSTALL_DIR/library"

    cat > "$INSTALL_DIR/library/EXTENSIONS.md" <<'LIB_EXTENSIONS_MD_EOF'
# Library Extensions Guide

This guide documents how consumers can add their own books to the library and the opt-out mechanics.

## Extending the Library

Consumers can add books by dropping files into the workspace `library/<role>/` tree (the same convention agents already read) and registering them in `library/README.md`'s consumer section.

The payload ships a `library/EXTENSIONS.md` guide documenting this, and the shipped register is never overwritten once the consumer edits it (no-clobber).

## Opt-Out Mechanics

`WITH_LIBRARY=false` installs NO shipped library books (zero redistribution/attribution surface), leaving only the extension docs + empty register; the rest of the agentic setup (AGENTS contract, agents, skills, opencode fragment) is unaffected and functional.

## No-Clobber Guarantee

Scaffold writes ONLY files on its shipped-file MANIFEST; consumer books and consumer-edited register entries survive, even across `OVERWRITE=true` refreshes.
LIB_EXTENSIONS_MD_EOF

    # Copy generic skills (checkpoint-notes, java-compile-fix, etc.)
    mkdir -p "$INSTALL_DIR/library/skills"

    cat > "$INSTALL_DIR/library/skills/checkpoint-notes.md" <<'CHECKPOINT_SKILL_EOF'
# Checkpoint Notes Skill

Maintain a lossless progress checkpoint (notes.md) for multi-session or easily-interrupted work. Use when a task spans sessions, the session may be context-compacted or die mid-flight, you must resume work without losing state, you are about to delegate a large unit of work, or you return after a compaction and need to reconstruct remaining work. Also covers uid-prefixed scratch artifacts.

Usage:
- Update status in real time; don't batch completions
- Mark `completed` only after the required work is actually done, including any required verification
- Keep exactly one `in_progress` while work remains
- If blocked or partial, keep it `in_progress` and add a follow-up todo describing the blocker
- Preserve user-provided commands verbatim (flags, args, order)
- Items should be specific and actionable; break large work into smaller steps
CHECKPOINT_SKILL_EOF

    cat > "$INSTALL_DIR/library/skills/java-compile-fix.md" <<'JAVA_COMPILE_SKILL_EOF'
# Java Compile/Fix Skill

Use when compiling, running, or debugging standalone Java CLI programs in this repo (e.g. scripts/WeatherCLI.java) — javac/java invocation and common Java gotchas like regex escape sequences.
JAVA_COMPILE_SKILL_EOF

    cat > "$INSTALL_DIR/library/skills/requesting-code-review.md" <<'REQUEST_REVIEW_SKILL_EOF'
# Requesting Code Review Skill

Use when completing tasks, implementing major features, or before merging to verify work meets requirements
REQUEST_REVIEW_SKILL_EOF

    cat > "$INSTALL_DIR/library/skills/serve-health.md" <<'SERVE_HEALTH_SKILL_EOF'
# Serve Health Skill

Use when diagnosing why the local model stack is down — llama-server not responding, bifrost 502s, or opencode auth/completion failures. Covers port checks, tmux sessions, and restart commands.
SERVE_HEALTH_SKILL_EOF

    cat > "$INSTALL_DIR/library/skills/skill-creator.md" <<'SKILL_CREATOR_SKILL_EOF'
# Skill Creator Skill

Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy.
SKILL_CREATOR_SKILL_EOF

    cat > "$INSTALL_DIR/library/skills/systematic-debugging.md" <<'SYSTEMATIC_DEBUG_SKILL_EOF'
# Systematic Debugging Skill

Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes
SYSTEMATIC_DEBUG_SKILL_EOF

    cat > "$INSTALL_DIR/library/skills/test-driven-development.md" <<'TDD_SKILL_EOF'
# Test-Driven Development Skill

Use when implementing any feature or bugfix, before writing implementation code
TDD_SKILL_EOF

    # Copy ai-researcher library subset
    mkdir -p "$INSTALL_DIR/library/ai-researcher"

    cat > "$INSTALL_DIR/library/ai-researcher/llama-cpp.mini.md" <<'LLAMA_CPP_MINI_MD_EOF'
# llama.cpp Reference (Tag b10360)

## Overview
- **llama.cpp**: GGML tensor library for high-performance inference of GGUF models.
- **llama-server**: Provides an OpenAI-compatible `/v1` API.

## Build & Architecture
- **Compilation**: Use CMake with `GGML_CUDA=ON`.
- **GPU Architectures**: Repo bakes in 80, 86, 89, 90, 120 (Ampere/Ada/Hopper/Blackwell). Turing (`75`) requires manual addition to `CMAKE_CUDA_ARCHITECTURES`.
- **Multi-GPU**: Supported via `--n-gpu-layers` and backend optimizations.

## Model & Quantization
- **GGUF Format**: Standard for llama.cpp inference.
- **Quantizations**: 
  - `Q4_K_M`, `Q4_K_L`: Balanced quality/size (preferred).
  - `Q8_0`, `F16`: Higher precision, higher memory usage.

## Context & KV Cache
- **Context Window**: Controlled by `--ctx-size`.
- **Parallel Processing**: Use `--parallel <n>` to define slots. Each slot has its own context.
- **KV Cache**: 
  - `--cache-type-k/v q4_0`: Quantized KV cache for memory efficiency.
  - `--flash-attn`: Enables Flash Attention for faster processing and lower memory.
  - `ctx_other`: Required by some architectures (e.g., Gemma4Assistant) to fit assistant layers.

## Speculative Decoding
- **Mechanism**: Uses a draft model to predict tokens, then validates with the main model.
- **Draft Models**: Use `--spec-draft-model` and `--spec-type draft-mtp`.
- **MTP (Multi-Token Prediction)**: Shared KV cache between draft and main models (e.g., `mtp-gemma-4-12b-it`).
- **Parameters**: 
  - `--spec-draft-n-max`: Max tokens to speculate.
  - `--spec-draft-ngl`: Number of GPU layers for the draft model.
- **Note**: Some models (e.g., Qwen3-0.6B) may show a net loss in acceptance rate; use with caution.

## llama-server Operations
- **Alias**: `--alias <id>` MUST match the `model` ID sent by opencode.
- **Networking**: `--host 0.0.0.0`, `--port <port>`.
- **Metrics**: `--metrics` enables performance tracking.
- **Reasoning**: Use `--reasoning off` to disable specific reasoning modes.
- **Batching**: `--ubatch-size` controls the number of tokens processed per batch.

## Grammar & Constrained Decoding
- **GBNF Grammars**: Use `--grammar` or `--grammar-file` to constrain output structure (e.g., JSON, Bash).
- **llguidance**: Advanced constrained decoding via grammars and logic.
- **Function Calling**: Achieved through grammar-based sampling of JSON schemas.
LLAMA_CPP_MINI_MD_EOF

    cat > "$INSTALL_DIR/library/ai-researcher/gemma-4-26b-a4b.mini.md" <<'GEMMA_4_26B_MINI_MD_EOF'
# gemma4-26b-a4b Mini Reference

[gemma4 reference documentation - condensed]
GEMMA_4_26B_MINI_MD_EOF

    # Copy release-it.mini.md
    cat > "$INSTALL_DIR/library/release-it.mini.md" <<'RELEASE_IT_MINI_MD_EOF'
# release-it.mini.md

Shared by all agents. Handles release versioning and publishing conventions.
RELEASE_IT_MINI_MD_EOF

    # Create scaffold.sh that copies payload into workspace (idempotent, skip-if-exists unless OVERWRITE)
    cat > "$INSTALL_DIR/scaffold.sh" <<'SCAFFOLD_SH_EOF'
#!/bin/sh
set -e

echo "Opencode-agents scaffold: copying payload to workspace"

INSTALL_DIR="${INSTALL_DIR:-/usr/local/share/opencode-agents}"
OVERWRITE="${OVERWRITE:-false}"
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Idempotent: skip if files already exist unless OVERWRITE
if [ "$OVERWRITE" = "true" ]; then
    echo "OVERWRITE=true — refreshing scaffold files (may overwrite existing workspace files)"
else
    # Check if scaffold already exists (skip if present unless consumer edited it)
    if [ -f "$WORKSPACE/AGENTS.md" ] && [ -f "$WORKSPACE/AGENTS_LIFECYCLE.md" ]; then
        echo "Scaffold already present (AGENTS.md + AGENTS_LIFECYCLE.md detected). Use OVERWRITE=true to refresh."
        exit 0
    fi
fi

# Copy AGENTS.md and AGENTS_LIFECYCLE.md to workspace (respecting OVERWRITE)
cp -f "$INSTALL_DIR/AGENTS.md" "$WORKSPACE/AGENTS.md"
cp -f "$INSTALL_DIR/AGENTS_LIFECYCLE.md" "$WORKSPACE/AGENTS_LIFECYCLE.md"

# Copy .opencode/agent/*.md files
mkdir -p "$WORKSPACE/.opencode/agent"
for f in "$INSTALL_DIR/.opencode/agent"/*.md; do
    [ -f "$f" ] && cp -f "$f" "$WORKSPACE/.opencode/agent/"
done

# Copy library/ books
cp -rf "$INSTALL_DIR/library/" "$WORKSPACE/library/"

# Copy library/EXTENSIONS.md guide (always copy, consumer edits survive OVERWRITE)
cp -f "$INSTALL_DIR/library/EXTENSIONS.md" "$WORKSPACE/library/EXTENSIONS.md"

echo "Scaffold complete. AGENTS.md + AGENTS_LIFECYCLE.md copied to workspace."
SCAFFOLD_SH_EOF
chmod 0755 "$INSTALL_DIR/scaffold.sh"

# Write opencode.json fragment file (primary agents build/architect + subagents with slot-pinned models, permissions, compaction, subagent_depth)
mkdir -p "$INSTALL_DIR"

cat > "$INSTALL_DIR/opencode.json.fragment" <<'OPENCODE_JSON_FRAGMENT_EOF'
{
  "provider": {
    "models": {
      "gemma4-26b-a4b": {
        "model": "local-gemma4-26b/gemma4-26b-a4b",
        "slot": "N"
      },
      "gemma4-31b-orchestrator": {
        "model": "google_gemma-4-31B-it-IQ2_XXS.gguf",
        "slot": "1"
      }
    },
    "enabled_providers": ["gemma4"],
    "x-bf-passthrough-extra-params": "",
    "setCacheKey": false
  },
  "agents": {
    "architect": {
      "model": "local-gemma4-26b/gemma4-26b-a4b",
      "slot": "N"
    },
    "researcher": {
      "model": "local-gemma4-26b/gemma4-26b-a4b",
      "slot": "N"
    },
    "reviewer": {
      "model": "local-gemma4-26b/gemma4-26b-a4b",
      "slot": "N"
    }
  },
  "subagent": {
    "depth": 2
  }
}
OPENCODE_JSON_FRAGMENT_EOF

# Install the opencode CLI itself (binary via the official installer).
# This is what makes `opencode serve` / `opencode` usable in the box;
# the payload above only ships the agent scaffold (AGENTS.md, library).
if ! command -v curl >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends curl >/dev/null 2>&1 || echo "WARNING: curl unavailable"
fi
if command -v opencode >/dev/null 2>&1; then
    echo "opencode CLI already installed: $(opencode --version 2>/dev/null || echo present)"
else
    echo "Installing opencode CLI (official installer)..."
    if curl -fsSL https://opencode.ai/install | bash; then
        echo "opencode CLI installed: $(opencode --version 2>/dev/null || echo present)"
    else
        echo "WARNING: opencode CLI install failed — run 'curl -fsSL https://opencode.ai/install | bash' manually"
    fi
fi

echo "Done! Opencode-agents feature activated."
echo "Scaffold scripts placed at $INSTALL_DIR/scaffold.sh"
echo "opencode.json.fragment placed at $INSTALL_DIR/opencode.json.fragment"
echo "Run scaffold.sh to copy payload into workspace."