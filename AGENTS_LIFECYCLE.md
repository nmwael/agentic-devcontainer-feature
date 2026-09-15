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
