#!/usr/bin/env bash
set -uo pipefail

# ============================================================================
# validate-contract.sh — Validate a contract's acceptance criteria are met
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BLUE}ℹ${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}✓${RESET}  %s\n" "$*"; }
fail()  { printf "${RED}✗${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }
header(){ printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") <contract-file> [OPTIONS]

Validate a contract's acceptance criteria and sensors, then
move to completed/ if everything passes.

${BOLD}Options:${RESET}
  -d, --dir DIR     Project directory (default: current directory)
  -n, --dry-run     Check only, don't move the contract
  -h, --help        Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0") .harness/contracts/active/20240115-add-auth.md
  $(basename "$0") .harness/contracts/active/*.md --dry-run
EOF
  exit 0
}

PROJECT_DIR="."
DRY_RUN=false
CONTRACT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)     PROJECT_DIR="$2"; shift 2 ;;
    -n|--dry-run) DRY_RUN=true;     shift   ;;
    -h|--help)    usage ;;
    -*)           fail "Unknown option: $1"; usage ;;
    *)
      if [[ -z "$CONTRACT_FILE" ]]; then
        CONTRACT_FILE="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$CONTRACT_FILE" ]]; then
  fail "Contract file path is required"
  echo ""
  usage
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Resolve contract file path
if [[ ! -f "$CONTRACT_FILE" ]]; then
  # Try relative to project dir
  if [[ -f "${PROJECT_DIR}/${CONTRACT_FILE}" ]]; then
    CONTRACT_FILE="${PROJECT_DIR}/${CONTRACT_FILE}"
  else
    fail "Contract file not found: ${CONTRACT_FILE}"
    exit 1
  fi
fi

CONTRACT_NAME="$(basename "$CONTRACT_FILE" .md)"
header "Validating Contract: ${CONTRACT_NAME}"

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARN=0

check_pass() { CHECKS_PASSED=$((CHECKS_PASSED + 1)); ok "$1"; }
check_fail() { CHECKS_FAILED=$((CHECKS_FAILED + 1)); fail "$1"; }
check_warn() { CHECKS_WARN=$((CHECKS_WARN + 1)); warn "$1"; }

# ---------------------------------------------------------------------------
# 1. Check contract status
# ---------------------------------------------------------------------------
header "Contract Status"
CONTRACT_STATUS=$(grep -m1 "^\*\*Status\*\*:" "$CONTRACT_FILE" 2>/dev/null || echo "")
if echo "$CONTRACT_STATUS" | grep -q "ACTIVE\|🟡"; then
  check_pass "Contract is ACTIVE"
elif echo "$CONTRACT_STATUS" | grep -q "DRAFT\|🔴"; then
  check_fail "Contract is still DRAFT — activate it first"
elif echo "$CONTRACT_STATUS" | grep -q "COMPLETE\|🟢"; then
  check_warn "Contract is already COMPLETE"
else
  check_warn "Could not determine contract status"
fi

# ---------------------------------------------------------------------------
# 2. Check acceptance criteria
# ---------------------------------------------------------------------------
header "Acceptance Criteria"
UNCHECKED=$(grep -c "^\- \[ \]" "$CONTRACT_FILE" 2>/dev/null || echo "0")
CHECKED=$(grep -c "^\- \[x\]" "$CONTRACT_FILE" 2>/dev/null || echo "0")
TOTAL=$((UNCHECKED + CHECKED))

if [[ "$TOTAL" -eq 0 ]]; then
  check_warn "No acceptance criteria found in contract"
elif [[ "$UNCHECKED" -gt 0 ]]; then
  check_fail "${UNCHECKED}/${TOTAL} acceptance criteria still unchecked"
  echo ""
  info "Unchecked criteria:"
  grep "^\- \[ \]" "$CONTRACT_FILE" | while read -r line; do
    printf "    ${YELLOW}○${RESET} %s\n" "${line#- [ ] }"
  done
else
  check_pass "All ${TOTAL} acceptance criteria checked"
fi

# ---------------------------------------------------------------------------
# 3. Check deliverable files exist
# ---------------------------------------------------------------------------
header "Deliverables"
# Extract file paths from the deliverables table (look for paths in backticks or after |)
DELIVERABLE_FILES=$(awk '/^## Deliverables/,/^## [^D]/' "$CONTRACT_FILE" | \
  grep -oE '`[^`]+\.[a-zA-Z]+`' | tr -d '`' || true)

if [[ -z "$DELIVERABLE_FILES" ]]; then
  check_warn "No deliverable files detected in contract table"
else
  while IFS= read -r file; do
    if [[ -f "${PROJECT_DIR}/${file}" ]]; then
      check_pass "Deliverable exists: ${file}"
    else
      check_fail "Deliverable missing: ${file}"
    fi
  done <<< "$DELIVERABLE_FILES"
fi

# ---------------------------------------------------------------------------
# 4. Run sensors
# ---------------------------------------------------------------------------
header "Sensor Validation"
SENSOR_SCRIPT="${PROJECT_DIR}/.harness/scripts/run-sensors.sh"
if [[ -x "$SENSOR_SCRIPT" ]]; then
  if bash "$SENSOR_SCRIPT" --dir "$PROJECT_DIR"; then
    check_pass "All sensors passed"
  else
    check_fail "One or more sensors failed"
  fi
else
  check_warn "run-sensors.sh not found — skipping sensor validation"
fi

# ---------------------------------------------------------------------------
# Summary & Decision
# ---------------------------------------------------------------------------
header "Validation Summary"
echo ""
printf "  ${GREEN}Passed:${RESET}   %d\n" "$CHECKS_PASSED"
printf "  ${RED}Failed:${RESET}   %d\n" "$CHECKS_FAILED"
printf "  ${YELLOW}Warnings:${RESET} %d\n" "$CHECKS_WARN"
echo ""

if [[ "$CHECKS_FAILED" -gt 0 ]]; then
  fail "Contract validation FAILED — ${CHECKS_FAILED} check(s) did not pass"
  echo ""
  info "Fix the failures above, then re-run this validator."
  exit 1
fi

if [[ "$CHECKS_WARN" -gt 0 ]]; then
  warn "Contract passed with ${CHECKS_WARN} warning(s) — review before completing"
fi

# ---------------------------------------------------------------------------
# Move to completed (if not dry-run)
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
  ok "Dry run — contract would be marked COMPLETE"
else
  COMPLETED_DIR="${PROJECT_DIR}/.harness/contracts/completed"
  mkdir -p "$COMPLETED_DIR"

  # Update status in contract
  sed -i.bak 's/🟡 ACTIVE/🟢 COMPLETE/g; s/🔴 DRAFT/🟢 COMPLETE/g' "$CONTRACT_FILE"
  rm -f "${CONTRACT_FILE}.bak"

  # Move to completed
  mv "$CONTRACT_FILE" "${COMPLETED_DIR}/"
  ok "Contract marked COMPLETE and moved to: ${COMPLETED_DIR}/$(basename "$CONTRACT_FILE")"

  # Update progress.md
  PROGRESS_FILE="${PROJECT_DIR}/.harness/memory/progress.md"
  if [[ -f "$PROGRESS_FILE" ]]; then
    TASK_DESC=$(awk '/^## Task Description/,/^---/' "$CONTRACT_FILE" 2>/dev/null | grep -v "^##\|^---" | head -1 | xargs || echo "$CONTRACT_NAME")
    echo "| $(date +%Y-%m-%d) | ${TASK_DESC} | ${CONTRACT_NAME} | All sensors passed ✓ |" >> "$PROGRESS_FILE"
    ok "Updated progress.md"
  fi
fi

echo ""
ok "Contract validation PASSED ✅"
