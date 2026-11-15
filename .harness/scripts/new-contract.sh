#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# new-contract.sh — Create a new task contract from a description
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ok()    { printf "${GREEN}✓${RESET}  %s\n" "$*"; }
err()   { printf "${RED}✗${RESET}  %s\n" "$*" >&2; }
header(){ printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") "task description"

Create a new task contract in .harness/contracts/active/

${BOLD}Options:${RESET}
  -d, --dir DIR     Project directory (default: current directory)
  -h, --help        Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0") "Add user authentication with JWT"
  $(basename "$0") "Refactor database layer to use connection pooling"
  $(basename "$0") "Fix pagination bug on /api/users endpoint"
EOF
  exit 0
}

PROJECT_DIR="."
TASK_DESC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir) PROJECT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) err "Unknown option: $1"; usage ;;
    *)
      if [[ -z "$TASK_DESC" ]]; then
        TASK_DESC="$1"
      else
        TASK_DESC="$TASK_DESC $1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$TASK_DESC" ]]; then
  err "Task description is required"
  echo ""
  usage
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
CONTRACTS_DIR="${PROJECT_DIR}/.harness/contracts/active"
mkdir -p "$CONTRACTS_DIR"

# Generate filename from timestamp and task description
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
# Slugify the task description for filename
SLUG=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//' | cut -c1-50)
CONTRACT_FILE="${CONTRACTS_DIR}/${TIMESTAMP}-${SLUG}.md"

# Load sensors if available
SENSORS_TABLE=""
if [[ -f "${PROJECT_DIR}/.harness/sensors.json" ]]; then
  if command -v jq &>/dev/null; then
    SENSORS_TABLE=$(jq -r '.sensors[] | "| \(.name) | `\(.command)` | ✅ |"' "${PROJECT_DIR}/.harness/sensors.json" 2>/dev/null || echo "| | | |")
  fi
fi
[[ -z "$SENSORS_TABLE" ]] && SENSORS_TABLE="| | | |"

cat > "$CONTRACT_FILE" <<CONTRACTEOF
# Task Contract

**ID**: ${TIMESTAMP}
**Created**: $(date +"%Y-%m-%d %H:%M:%S")
**Status**: 🔴 DRAFT

> ⚠️ This contract is a DRAFT. Review and update all sections before changing
> status to 🟡 ACTIVE. No work begins until status is ACTIVE.

---

## Task Description

${TASK_DESC}

---

## Deliverables

| # | File/Output | Format | Location |
|---|------------|--------|----------|
| 1 | | | |
| 2 | | | |

---

## Constraints

- **Dependencies**: [What this task depends on — other files, services, APIs]
- **Forbidden Patterns**: [What must NOT be used or changed]
- **Budget**: Max __ files changed, max 4 retry cycles per sensor
- **Time Estimate**: [rough estimate]

---

## Non-Goals

> Explicit list of what this task must NOT do. Prevents scope creep.

- [ ] [Thing explicitly excluded #1]
- [ ] [Thing explicitly excluded #2]

---

## Acceptance Criteria

> Observable, testable conditions. The task is COMPLETE only when ALL are checked.

- [ ] [Criterion 1 — must be verifiable by a sensor or human inspection]
- [ ] [Criterion 2]
- [ ] [Criterion 3]
- [ ] All existing tests still pass
- [ ] Map updated if files were added/moved

---

## Required Sensors

| Sensor | Command | Must Pass |
|--------|---------|-----------|
${SENSORS_TABLE}

---

## Subtasks (Graph Decomposition)

> For tasks > 200 lines of changes, decompose here. Each subtask is validated independently.

- [ ] **Subtask 1**: [description] → validates with [sensor]
- [ ] **Subtask 2**: [description] → validates with [sensor]
- [ ] **Adversarial Review**: Actively try to break the implementation

---

## Execution Log

> Claude fills this in as work progresses. Each attempt is numbered.

| Attempt | Action | Sensor Result | Timestamp | Notes |
|---------|--------|---------------|-----------|-------|
| | | | | |

---

## Halt Report (if applicable)

> Fill this ONLY if the task is halted after exhausting retry budget.

**Reason**:
**Attempts Made**:
**All Sensor Outputs**:
**Diagnosis**:
**Suggested Next Steps for Human**:
CONTRACTEOF

header "Contract Created"
echo ""
printf "${BOLD}  Task:${RESET}     %s\n" "$TASK_DESC"
printf "${BOLD}  File:${RESET}     %s\n" "$CONTRACT_FILE"
printf "${BOLD}  Status:${RESET}   🔴 DRAFT\n"
echo ""
printf "${CYAN}  Next steps:${RESET}\n"
printf "    1. Edit the contract to fill in deliverables, constraints, and acceptance criteria\n"
printf "    2. Change status to 🟡 ACTIVE\n"
printf "    3. Tell Claude: ${BOLD}\"Execute contract ${TIMESTAMP}\"${RESET}\n"
echo ""

ok "Contract ready for review: ${CONTRACT_FILE}"
