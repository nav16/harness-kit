# Harness Engineering Kit

> **The model is the CPU. The context window is the RAM. This kit is the operating system.**

A portable, CLAUDE.md-based harness that transforms Claude Code from a raw reasoning engine into a disciplined execution environment with contracts, sensors, durable memory, and task decomposition.

## The Problem

Most people respond to AI failures by editing the prompt, switching models, or upgrading their subscription. The model still forgets instructions. It still skips verification. It still claims success on broken code.

**The problem sits outside the model weights. The problem sits in the environment.**

That environment is the **harness**. Designing it is **harness engineering**.

## The Three Layers

```
┌─────────────────────────────────────────────┐
│  Graph Layer (work allocation)              │
│  ├─ Task decomposition for large changes    │
│  ├─ Adversarial self-review                 │
│  └─ Isolated subtask validation             │
├─────────────────────────────────────────────┤
│  Loop Layer (evidence gates)                │
│  ├─ Auto-detected test runners & linters    │
│  ├─ Execution budgets (max 4 retries)       │
│  └─ Raw output feedback (never self-eval)   │
├─────────────────────────────────────────────┤
│  Harness Layer (environment + memory)       │
│  ├─ Durable memory files (survive resets)   │
│  ├─ Compact project maps (not doc dumps)    │
│  ├─ Task contracts (scope + acceptance)     │
│  └─ Dual-encoded rules (intent + gate)      │
└─────────────────────────────────────────────┘
```

## Quick Start

### 1. Copy to your project

```bash
cp -r harness-kit/.harness /path/to/your-project/
cp harness-kit/CLAUDE.md /path/to/your-project/
```

### 2. Or use the init script

```bash
cd /path/to/your-project
/path/to/harness-kit/.harness/scripts/init-harness.sh --dir .
```

The init script:
- Creates the `.harness/` directory structure
- Installs CLAUDE.md
- Auto-detects your test frameworks and linters (sensors)
- Generates a compact project map
- Creates durable memory file templates
- Is **idempotent** — safe to re-run, never overwrites your data

### 3. Open Claude Code

Claude Code auto-loads `CLAUDE.md` and operates under harness rules. It will:
- Require a **contract** before starting any work
- Run **sensors** (tests, type checkers, linters) after every change
- Store decisions in **durable memory** that survives session resets
- **Decompose** large tasks into validated subtasks
- **HALT** and report diagnostics instead of silently failing

## What's Inside

```
harness-kit/
├── CLAUDE.md                          # The operating manual (auto-loaded)
├── README.md                          # This file
└── .harness/
    ├── contracts/
    │   ├── active/                    # Current task contracts
    │   └── completed/                 # Finished contracts (audit trail)
    ├── memory/
    │   ├── decisions.md               # Architecture decisions log
    │   ├── bugs.md                    # Known issues tracker
    │   ├── preferences.md             # Coding style & workflow prefs
    │   └── progress.md                # What's done, what's next
    ├── templates/
    │   └── contract.md                # Task contract template
    ├── scripts/
    │   ├── init-harness.sh            # Initialize harness in any project
    │   ├── detect-sensors.sh          # Auto-detect test/lint tools
    │   ├── generate-map.sh            # Generate compact project map
    │   ├── new-contract.sh            # Create a task contract from description
    │   ├── run-sensors.sh             # Run all sensors with reporting
    │   └── validate-contract.sh       # Validate & close a contract
    ├── sensor-runs/                   # Sensor execution logs
    ├── sensors.json                   # Detected validation tools
    └── map.md                         # Compact project structure index
```

## The 5 Core Jobs

### 1. Contracts (Automated ✅)
Every request becomes a formal contract with deliverables, constraints, non-goals, and acceptance criteria. No ambiguity. No scope creep. No "the model decided it was done."

```bash
.harness/scripts/new-contract.sh "Add JWT authentication to the API"
```

### 2. Project Maps (Automated ✅)
A compact index of your project structure. Claude reads the map to find files instead of asking you to paste code into chat.

```bash
.harness/scripts/generate-map.sh
```

### 3. Durable Memory (Guidelines 📝)
Architecture decisions, bugs, preferences, and progress stored in markdown files that survive session resets. Claude reads them at the start of every session.

### 4. Sensors (Automated ✅)
Auto-detects your test runners, type checkers, and linters. Claude runs them after every change and only reports success when sensors confirm it.

```bash
.harness/scripts/detect-sensors.sh    # Find available tools
.harness/scripts/run-sensors.sh       # Run all sensors
```

Supports: Node.js (jest/vitest/mocha/tsc/eslint/prettier), Python (pytest/mypy/ruff/black), Rust (cargo), Go, Ruby (rspec/rubocop), Make, Docker, Git pre-commit hooks.

### 5. Graph Decomposition (Automated ✅)
Tasks over ~200 lines of changes are decomposed into subtasks, each validated independently, with an adversarial review pass at the end.

## Key Principles

| Principle | What It Means |
|-----------|--------------|
| **No Work Without a Contract** | Claude generates a contract before touching code |
| **No Claim Without Evidence** | Success = sensor output, not Claude's opinion |
| **Dual-Encoding** | Critical rules exist as both instructions AND mechanical gates |
| **Max 4 Retries** | After 4 failed attempts, Claude HALTs and reports diagnostics |
| **Map, Not Encyclopedia** | Read the index, fetch one file — never dump everything |
| **Memory Survives Resets** | Decisions and progress are written to disk immediately |

## Works With

- ✅ New (greenfield) projects
- ✅ Existing codebases
- ✅ Any language with testable output
- ✅ Claude Code (primary target)
- 🔄 Adaptable to Cursor (rename CLAUDE.md → .cursorrules)

## License

Internal tooling. Use it, share it, adapt it.
