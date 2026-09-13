# Reference Books

Condensed reference books organized by agent role.

Books in `architect/`, `coder/`, `researcher/`, `reviewer/` and `release-it.mini.md` are sourced from [ciembor/agent-rules-books](https://github.com/ciembor/agent-rules-books/) (MIT License). Books in `ai-researcher/` and `coder/java.mini.md` are original condensed references for this repo, grounded in the repo's own code and in Oracle/Quarkus documentation and the llama.cpp documentation at the pinned tag b10360. `architect/autonomous-agent-loops.mini.md` is an original condensed reference grounded in the freeCodeCamp "60 Patterns for Building Autonomous Systems" guide and web sources (Reflexion, Tree-of-Thought, ReAct, CrewAI flows), with repo-specific decision rules for the boxforsine verification-gate loops. `ai-researcher/gemma-4-26b-a4b.mini.md` is an original condensed reference grounded in Google Gemma 4 documentation, llama.cpp docs/issues/discussions, unsloth docs, and r/LocalLLaMA sources (URLs inline), written 2026-09-11; it pairs with `llama-cpp.mini.md` for the repo's 26B-A4B IQ2_M stack.

```
library/
├── architect/
│   ├── clean-architecture.mini.md
│   ├── patterns-of-enterprise-application-architecture.mini.md
│   ├── domain-driven-design-distilled.mini.md
│   └── autonomous-agent-loops.mini.md
├── ai-researcher/
│   ├── llama-cpp.mini.md
│   ├── gemma-4-26b-a4b.mini.md
│   └── project_stack.md
├── coder/
│   ├── clean-code.mini.md
│   ├── java.mini.md
│   ├── refactoring.mini.md
│   ├── tdd-software.mini.md
│   └── the-pragmatic-programmer.mini.md
├── researcher/
│   └── a-philosophy-of-software-design.mini.md
├── reviewer/
│   ├── code-complete.mini.md
│   └── working-effectively-with-legacy-code.mini.md
└── release-it.mini.md
```

The `@3d-designer` books (`tdd-mechanical.mini.md`, `design_standards.mini.md`) live at `3dprints/library/` (same relative layout as the original repo).

| Role | Books |
| :--- | :--- |
| All agents | `release-it.mini.md` |
| @architect | `architect/clean-architecture.mini.md`, `architect/patterns-of-enterprise-application-architecture.mini.md`, `architect/domain-driven-design-distilled.mini.md`, `architect/autonomous-agent-loops.mini.md` |
| @coder | `coder/clean-code.mini.md`, `coder/refactoring.mini.md`, `coder/the-pragmatic-programmer.mini.md`, `coder/java.mini.md`, `3dprints/library/tdd-mechanical.mini.md`, `coder/tdd-software.mini.md` |
| @ai-researcher | `ai-researcher/llama-cpp.mini.md`, `ai-researcher/gemma-4-26b-a4b.mini.md` |
| @researcher | `researcher/a-philosophy-of-software-design.mini.md` |
| @reviewer | `reviewer/code-complete.mini.md`, `reviewer/working-effectively-with-legacy-code.mini.md` |
| @ui | no dedicated book yet |
| @artist | no dedicated book yet |
| @3d-designer | `3dprints/library/design_standards.mini.md` |

*Machine-readable matrix: `manifest.json` (this table is generated from it).*

Layout notes:
- The llama.cpp book moved from `llama.cpp/` to `ai-researcher/`: llama.cpp is a research/ML-adjacent topic, owned by the `ai-researcher` agent.
- The java book moved from `java/` to `coder/`: Java is a coder concern; per maintainer directive it is not shared with `researcher`/`reviewer`.
- `domainbooks/` (Danish crisis/firefighter/stormflood/cyberattack reference books from the original lab repo) is intentionally not shipped here.
