coder:
  description: Writing new code, editing files, fixing bugs, implementing features
  model: local-gemma4-26b/gemma4-26b-a4b-s1
  mode: subagent
researcher:
  description: Exploring the codebase (+ web via webfetch), searching for patterns, understanding architecture
  model: local-gemma4-26b/gemma4-26b-a4b-s2
  mode: subagent
reviewer:
  description: Reviewing code for bugs, style, security issues, and suggesting improvements
  model: local-gemma4-26b/gemma4-26b-a4b-s3
  mode: subagent
ai-researcher:
  description: AI research: codebase + web research, library-aware (reads its role's books)
  model: local-gemma4-26b/gemma4-26b-a4b-s4
  mode: subagent
3d-designer:
  description: Specializes in 3D printing design and STL generation
  model: local-gemma4-26b/gemma4-26b-a4b-s4
  mode: subagent
ui:
  description: Designing user interfaces and turning them into UI code (HTML/CSS)
  model: local-gemma4-26b/gemma4-26b-a4b-s4
  mode: subagent
artist:
  description: Visual assets and artwork as code (SVG/CSS), image analysis via Gemma4 vision
  model: local-gemma4-26b/gemma4-26b-a4b-s4
  mode: subagent
