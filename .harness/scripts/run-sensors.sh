#!/usr/bin/env bash
set -uo pipefail

# ============================================================================
# run-sensors.sh — Run all configured sensors and report results
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
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Run all sensors from .harness/sensors.json in priority order.

${BOLD}Options:${RESET}
  -d, --dir DIR       Project directory (default: current directory)
  -s, --sensor NAME   Run only the named sensor
  -v, --verbose       Show full command output (not just summary)
  -h, --help          Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0")
  $(basename "$0") --sensor unit-tests
  $(basename "$0") --verbose
EOF
  exit 0
}

PROJECT_DIR="."
FILTER_SENSOR=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)    PROJECT_DIR="$2"; shift 2 ;;
    -s|--sensor) FILTER_SENSOR="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -h|--help)   usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SENSORS_FILE="${PROJECT_DIR}/.harness/sensors.json"
RUNS_DIR="${PROJECT_DIR}/.harness/sensor-runs"

if [[ ! -f "$SENSORS_FILE" ]]; then
  fail "No sensors.json found at ${SENSORS_FILE}"
  info "Run .harness/scripts/detect-sensors.sh first"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  fail "jq is required to parse sensors.json"
  info "Install with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

# Create runs directory
mkdir -p "$RUNS_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${RUNS_DIR}/${TIMESTAMP}.log"

# ---------------------------------------------------------------------------
# Parse sensors and sort by priority
# ---------------------------------------------------------------------------
SENSOR_COUNT=$(jq '.sensors | length' "$SENSORS_FILE")
if [[ "$SENSOR_COUNT" -eq 0 ]]; then
  warn "No sensors configured in ${SENSORS_FILE}"
  exit 0
fi

header "Running ${SENSOR_COUNT} sensor(s)"
echo "Log: ${LOG_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Run sensors in priority order
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
RESULTS=()

# Get sensors sorted by priority
SORTED_SENSORS=$(jq -r '.sensors | sort_by(.priority) | .[] | @base64' "$SENSORS_FILE")

{
  echo "========================================="
  echo "Sensor Run: ${TIMESTAMP}"
  echo "Project:    ${PROJECT_DIR}"
  echo "========================================="
  echo ""
} > "$LOG_FILE"

for encoded in $SORTED_SENSORS; do
  SENSOR=$(echo "$encoded" | base64 --decode)
  NAME=$(echo "$SENSOR" | jq -r '.name')
  COMMAND=$(echo "$SENSOR" | jq -r '.command')
  TYPE=$(echo "$SENSOR" | jq -r '.type')
  PRIORITY=$(echo "$SENSOR" | jq -r '.priority')

  # Filter if specific sensor requested
  if [[ -n "$FILTER_SENSOR" && "$NAME" != "$FILTER_SENSOR" ]]; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  printf "${BOLD}  [P%s] %-20s${RESET} %s ... " "$PRIORITY" "$NAME" "$COMMAND"

  # Log header
  {
    echo "-----------------------------------------"
    echo "Sensor: ${NAME}"
    echo "Command: ${COMMAND}"
    echo "Type: ${TYPE}"
    echo "Priority: ${PRIORITY}"
    echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "-----------------------------------------"
  } >> "$LOG_FILE"

  # Run the sensor
  START_TIME=$(date +%s)
  set +e
  OUTPUT=$(cd "$PROJECT_DIR" && eval "$COMMAND" 2>&1)
  EXIT_CODE=$?
  set -e
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  # Log output
  {
    echo "$OUTPUT"
    echo ""
    echo "Exit code: ${EXIT_CODE}"
    echo "Duration: ${DURATION}s"
    echo ""
  } >> "$LOG_FILE"

  if [[ $EXIT_CODE -eq 0 ]]; then
    printf "${GREEN}PASS${RESET} (${DURATION}s)\n"
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS+=("PASS|${NAME}|${COMMAND}|${DURATION}s")
  else
    printf "${RED}FAIL${RESET} (${DURATION}s)\n"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("FAIL|${NAME}|${COMMAND}|${DURATION}s")

    # Show output on failure (or if verbose)
    if [[ "$VERBOSE" == true ]] || true; then
      echo ""
      echo "$OUTPUT" | head -30
      if [[ $(echo "$OUTPUT" | wc -l) -gt 30 ]]; then
        echo "  ... (truncated — see full log: ${LOG_FILE})"
      fi
      echo ""
    fi
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Sensor Results"
echo ""
printf "  ${BOLD}%-6s %-20s %-30s %s${RESET}\n" "STATUS" "SENSOR" "COMMAND" "TIME"
printf "  %-6s %-20s %-30s %s\n" "──────" "────────────────────" "──────────────────────────────" "────"

for result in "${RESULTS[@]}"; do
  IFS='|' read -r status name cmd duration <<< "$result"
  if [[ "$status" == "PASS" ]]; then
    printf "  ${GREEN}%-6s${RESET} %-20s %-30s %s\n" "$status" "$name" "$cmd" "$duration"
  else
    printf "  ${RED}%-6s${RESET} %-20s %-30s %s\n" "$status" "$name" "$cmd" "$duration"
  fi
done

echo ""
printf "  ${GREEN}Passed:${RESET}  %d\n" "$PASS_COUNT"
printf "  ${RED}Failed:${RESET}  %d\n" "$FAIL_COUNT"
[[ $SKIP_COUNT -gt 0 ]] && printf "  ${YELLOW}Skipped:${RESET} %d\n" "$SKIP_COUNT"
printf "  ${BOLD}Log:${RESET}     %s\n" "$LOG_FILE"
echo ""

# Exit with failure if any sensor failed
if [[ $FAIL_COUNT -gt 0 ]]; then
  fail "${FAIL_COUNT} sensor(s) failed"
  exit 1
else
  ok "All sensors passed"
  exit 0
fi
