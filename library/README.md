# Reference Books

Condensed reference books organized by agent role.

Books in `architect/`, `coder/`, `researcher/`, `reviewer/` and `release-it.mini.md` are sourced from [ciembor/agent-rules-books](https://github.com/ciembor/agent-rules-books/) (MIT License). `coder/java.mini.md` is an original condensed reference for this repo, grounded in the repo's own code and in Oracle/Quarkus documentation. `architect/autonomous-agent-loops.mini.md` is an original condensed reference grounded in the freeCodeCamp "60 Patterns for Building Autonomous Systems" guide and web sources (Reflexion, Tree-of-Thought, ReAct, CrewAI flows), with repo-specific decision rules for the boxforsine verification-gate loops.

```
library/
├── architect/
│   ├── clean-architecture.mini.md
│   ├── patterns-of-enterprise-application-architecture.mini.md
│   ├── domain-driven-design-distilled.mini.md
│   └── autonomous-agent-loops.mini.md
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

| Role | Books |
| :--- | :--- |
| All agents | `release-it.mini.md` |
| @architect | `architect/clean-architecture.mini.md`, `architect/patterns-of-enterprise-application-architecture.mini.md`, `architect/domain-driven-design-distilled.mini.md`, `architect/autonomous-agent-loops.mini.md` |
| @coder | `coder/clean-code.mini.md`, `coder/refactoring.mini.md`, `coder/the-pragmatic-programmer.mini.md`, `coder/java.mini.md`, `coder/tdd-software.mini.md` |
| @researcher | `researcher/a-philosophy-of-software-design.mini.md` |
| @reviewer | `reviewer/code-complete.mini.md`, `reviewer/working-effectively-with-legacy-code.mini.md` |
| @ui | no dedicated book yet |
| @artist | no dedicated book yet |

*Machine-readable matrix: `manifest.json` (this table is generated from it).*

Layout notes:
- The java book moved from `java/` to `coder/`: Java is a coder concern; per maintainer directive it is not shared with `researcher`/`reviewer`.
- `domainbooks/` (Danish crisis/firefighter/stormflood/cyberattack reference books from the original lab repo) is intentionally not shipped here.
