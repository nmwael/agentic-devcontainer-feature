# Checkpoint Notes Skill

Maintain a lossless progress checkpoint (notes.md) for multi-session or easily-interrupted work. Use when a task spans sessions, the session may be context-compacted or die mid-flight, you must resume work without losing state, you are about to delegate a large unit of work, or you return after a compaction and need to reconstruct remaining work. Also covers uid-prefixed scratch artifacts.

Usage:
- Update status in real time; don't batch completions
- Mark `completed` only after the required work is actually done, including any required verification
- Keep exactly one `in_progress` while work remains
- If blocked or partial, keep it `in_progress` and add a follow-up todo describing the blocker
- Preserve user-provided commands verbatim (flags, args, order)
- Items should be specific and actionable; break large work into smaller steps