# OBEY Autonomous Agent Loops by Architect Team

## When to use

- Implementing multi-turn agentic workflows where a single pass is insufficient for complex reasoning, code generation, or geometry (CAD/STL) generation.
- Designing systems that must self-correct, refine a plan, or iterate toward an objective (e.g., a box for an OLED screen whose lid must mate without "swimming").
- Building agents that autonomously navigate tool outputs to reach a goal, where the quality of the first candidate is unknown and a better result is obtained by iterating on a scored candidate.
- Whenever a flow must "loop and produce better and better results" rather than emit a single fixed output.

## Primary bias to correct

- **The Infinite Spin:** A loop without a measurable, reliable signal is spinning, not improving. Loops must optimize against a concrete, objective score or PASS/FAIL gate — never against gut feel or the agent's own claim.
- **Silent Success:** Agents claiming completion without verifiable side effects or state changes on disk. Completion must be shown by artifacts that exist and pass checks.
- **Goal Drift:** The agent wandering off the primary objective through unbounded recursive sub-task generation.
- **Single-Output Fallacy:** Emitting one candidate and stopping, when N candidates, each verified and scored, would yield a demonstrably better result and a record of the best.

## Decision rules

- **Signal Requirement:** Every loop iteration MUST produce a measurable delta (a score, a new file, a passed test). If no delta is detected, trigger an "Exhaustion" state instead of spinning.
- **Verification as Reward:** In this repo, use tool outputs as the objective reward signal. For STL geometry candidates, run trimesh manifoldness checks (watertight, correct facet normals, non-self-intersecting) on both base tray and lid and score each pair; feed that score back into the loop.
- **Feedback Design:** Use N-candidate generation -> per-candidate verification -> graded score aggregation -> PASS/FAIL gates. The loop input on iteration k+1 is the measured score from iteration k, not the agent's opinion.
- **Candidate Management:** Give every candidate a DISTINCT output filename (e.g., `design_1_base.stl`, `design_2_base.stl`, ...). N proposals that all write the same shared filename silently overwrite each other and destroy the very artifacts the loop needs to compare.
- **Select and Iterate on the Best:** After scoring N candidates, select the highest-scoring one as the base for the next refinement pass; do not let the loop thrash among equal or un-scored candidates.
- **Bounded Iteration:** Every loop MUST have a `MAX_FIX_ITERATIONS` or explicit step budget. On exhaustion the agent MUST report failure and request human intervention (HITL), never loop forever.
- **Artifact Preservation:** Preserve all N artifacts generated during the loop. Never trust unverified success; verify every claimed artifact exists on disk before reporting done.
- **Anti-Infinite-Loop Safeguards:** Track iteration count, staleness of the best score, and convergence. If the best score plateaus across N iterations, stop and report the best candidate rather than continuing.
- **HITL Gates:** Place human approve/reject gates at critical junctions (plan approval, final selection) and an off-switch. An autonomous loop must degrade to a human decision when it cannot converge.

## Trigger rules

- **Reflexion:** Trigger when a verification step fails; the agent must analyze the failure feedback, form a critique, and generate a new plan/attempt informed by that critique.
- **ReAct:** Trigger during real-time tool interaction where each action's observation informs the next thought/action. Interleave reasoning and acting.
- **Plan-Then-Execute:** Trigger for complex multi-file changes; generate a full plan -> execute -> verify the entire plan against its acceptance criteria.
- **Adaptive Replanner:** Trigger when a sub-task fails repeatedly or a "Goal Drift" detector fires; re-plan around the blocker instead of re-trying the same failing step.
- **Tree-of-Thought:** Trigger when multiple valid candidate paths exist; explore branches, score each, prune low-scoring ones, and deepen high-scoring ones.
- **Repetition Gate:** Trigger when the same candidate or the same failing step recurs without improvement; switch strategies or escalate to HITL rather than retrying blindly.

## Final checklist

- Does the loop have a defined exit condition (Success / Failure / Exhaustion)?
- Is there a measured, objective score or PASS/FAIL signal driving optimization (not the agent's self-report)?
- Do all N candidates get distinct filenames so none are overwritten before comparison?
- Does the loop select/iterate on the best-scoring candidate and preserve all N artifacts?
- Is there an anti-infinite-loop safeguard (MAX_FIX_ITERATIONS, plateau detection, staleness)?
- Does the system handle "Tool Spoofing" via side-effect auditing (verify files exist and pass checks)?
- Does the loop degrade gracefully to a human decision (HITL gate) when it cannot converge?
- Repo-specific: do the OpenMira workflow design nodes emit distinct STL names, and does the verification gate's score become the loop's reward?

## Sources

- freeCodeCamp, "The AI Agent Engineer's Guide: 60 Patterns for Building Autonomous Systems": https://www.freecodecamp.org/news/ai-agent-engineers-guide-60-patterns-for-building-autonomous-systems-book/
- Reflexion: Language Agents with Verbal Reinforcement Learning (Shinn et al.): https://arxiv.org/abs/2303.11366
- Tree of Thoughts: Deliberate Problem Solving with Large Language Models (Yao et al.): https://arxiv.org/abs/2305.10601
- ReAct: Synergizing Reasoning and Acting in Language Models (Yao et al.): https://arxiv.org/abs/2210.03629
- CrewAI Flow documentation (router, self-healing, nested flow patterns): https://docs.crewai.com/concepts/flows
- Anthropic, "Building Effective Agents": https://www.anthropic.com/research/building-effective-agents

## Control-systems roots of the agent loop (Autonomous-Systems-Guide)

The loop patterns in this book are not software-only inventions — they are the same closed-loop feedback architecture that robotics and control theory have used for decades. The following mappings condense mikeroyal/Autonomous-Systems-Guide (which aggregates the MATLAB, ROS, and simulator ecosystem) down to the design rules an agent-loop architect actually needs.

### Sense -> Plan -> Act (perceive, decide, act)

The canonical autonomous-system loop is perception -> planning -> action/control. An agent loop is the identical shape: observe the current state, form a plan, execute a step, then loop on the observed result. Design every agent loop with an explicit "sense" stage (read state/artifacts) before "plan", and an "act" stage (tool call producing a verifiable side effect) before re-sensing — do not let planning run ahead of sensing.

> "The toolbox includes algorithms for mapping, localization, path planning, path following, and motion control." - Robotics System Toolbox (Autonomous-Systems-Guide, Robotics Tools and Frameworks)

### Model Predictive Control = replan-a-little, never commit to the whole path

MPC solves an optimization over a prediction horizon, executes only the first step, then re-solves on the next tick using fresh state. Translate this to agents: plan a bounded horizon, execute only the first action, re-observe, and re-plan. This is the engineering basis for the book's ReAct trigger and its rule to never commit to a full plan that cannot be re-derived from the next observation.

> "The toolbox lets you specify plant and disturbance models, horizons, constraints, and weights. By running closed-loop simulations, you can evaluate controller performance." - Model Predictive Control Toolbox (Autonomous-Systems-Guide, MATLAB Tools)

### Reinforcement Learning = iteration-toward-reward, not fixed output

A policy is not written in one pass; it is trained by iterating on a reward signal over many episodes (DQN, PPO, SAC, DDPG). This is the machine-learning form of the book's "Verification as Reward": every loop iteration must consume an objective reward (a score, a passed test) and adjust the next candidate accordingly. If a step never changes the reward, stop — that is the rolling plateau the book's anti-infinite-loop safeguards detect.

> "training policies using reinforcement learning algorithms, including DQN, PPO, SAC, and DDPG ... to implement controllers and decision-making algorithms for complex applications." - Reinforcement Learning Toolbox (Autonomous-Systems-Guide, MATLAB Tools)

### Simulation-in-the-loop / hardware-in-the-loop = verify in a safe harness first

Autonomous systems are not first validated in the field; they are tested against a simulator via software-in-the-loop (SIL) or hardware-in-the-loop (HIL) to catch failures cheaply before deployment. Translate this to agents: cheap, deterministic checks (manifoldness, PASS/FAIL gates, score aggregation) are the simulation harness; they run every candidate before a human (HITL) approves the winner. Never deploy an agent action that did not first pass its simulation.

> "supports software-in-the-loop simulation ... and hardware-in-the-loop ... for physically and visually realistic simulations." - Microsoft AirSim (Autonomous-Systems-Guide, Autonomous Systems Tools)

### Sources (this section)

- mikeroyal, "Autonomous Systems Guide": https://github.com/mikeroyal/Autonomous-Systems-Guide (MATLAB Toolboxes: Model Predictive Control, Reinforcement Learning, Robotics System Toolbox; AirSim section)

