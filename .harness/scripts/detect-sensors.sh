#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# detect-sensors.sh — Auto-detect validation tools in the current project
# Part of the Harness Engineering Kit
# ============================================================================

# ---------------------------------------------------------------------------
# Colors & formatting
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BLUE}ℹ${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}✓${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }
err()   { printf "${RED}✗${RESET}  %s\n" "$*" >&2; }
header(){ printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Auto-detect available validation tools (sensors) in the current project.

${BOLD}Options:${RESET}
  -d, --dir DIR     Project directory to scan (default: current directory)
  -o, --output FILE Output path for sensors.json (default: .harness/sensors.json)
  -q, --quiet       Suppress informational output
  -h, --help        Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0")
  $(basename "$0") --dir /path/to/project
  $(basename "$0") --output custom-sensors.json
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Defaults & argument parsing
# ---------------------------------------------------------------------------
PROJECT_DIR="."
OUTPUT_FILE=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)    PROJECT_DIR="$2"; shift 2 ;;
    -o|--output) OUTPUT_FILE="$2";  shift 2 ;;
    -q|--quiet)  QUIET=true;        shift   ;;
    -h|--help)   usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="${PROJECT_DIR}/.harness/sensors.json"

log() { $QUIET || info "$@"; }
logok() { $QUIET || ok "$@"; }

# ---------------------------------------------------------------------------
# Sensor collection
# ---------------------------------------------------------------------------
SENSORS=()        # each entry is a JSON object string
PROJECT_TYPE=""
DETECTED_TYPES=() # track all detected project types

# Helper: add a sensor entry
add_sensor() {
  local name="$1" command="$2" type="$3" priority="$4" source="$5"
  SENSORS+=("$(cat <<SENSOR
    {
      "name": "${name}",
      "command": "${command}",
      "type": "${type}",
      "priority": ${priority},
      "detected_from": "${source}"
    }
SENSOR
  )")
  logok "Detected sensor: ${name} (${command})"
}

# Helper: check if a command is available
has_cmd() { command -v "$1" &>/dev/null; }

# Helper: check if a JSON file contains a key path (for package.json)
pkg_has_script() {
  local script_name="$1"
  local pkg="${PROJECT_DIR}/package.json"
  if has_cmd jq; then
    jq -e ".scripts[\"${script_name}\"]" "$pkg" &>/dev/null
  else
    grep -q "\"${script_name}\"" "$pkg" 2>/dev/null
  fi
}

pkg_has_dep() {
  local dep="$1"
  local pkg="${PROJECT_DIR}/package.json"
  if has_cmd jq; then
    jq -e "(.dependencies[\"${dep}\"] // .devDependencies[\"${dep}\"])" "$pkg" &>/dev/null
  else
    grep -q "\"${dep}\"" "$pkg" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# Node.js / JavaScript / TypeScript detection
# ---------------------------------------------------------------------------
detect_node() {
  local pkg="${PROJECT_DIR}/package.json"
  [[ -f "$pkg" ]] || return 0

  header "Node.js project detected (package.json)"
  DETECTED_TYPES+=("node")

  # Test scripts
  if pkg_has_script "test"; then
    add_sensor "unit-tests" "npm test" "test" 2 "package.json"
  fi

  # Vitest
  if pkg_has_dep "vitest" || pkg_has_script "test:unit"; then
    if ! pkg_has_script "test"; then
      add_sensor "vitest" "npx vitest run" "test" 2 "package.json"
    fi
  fi

  # Jest
  if pkg_has_dep "jest" && ! pkg_has_dep "vitest"; then
    if ! pkg_has_script "test"; then
      add_sensor "jest" "npx jest" "test" 2 "package.json"
    fi
  fi

  # Mocha
  if pkg_has_dep "mocha"; then
    if ! pkg_has_script "test"; then
      add_sensor "mocha" "npx mocha" "test" 2 "package.json"
    fi
  fi

  # TypeScript compiler
  if pkg_has_dep "typescript" || [[ -f "${PROJECT_DIR}/tsconfig.json" ]]; then
    add_sensor "typescript" "npx tsc --noEmit" "type-check" 1 "package.json"
  fi

  # ESLint
  if pkg_has_dep "eslint" || [[ -f "${PROJECT_DIR}/.eslintrc" ]] || [[ -f "${PROJECT_DIR}/.eslintrc.js" ]] || [[ -f "${PROJECT_DIR}/.eslintrc.json" ]] || [[ -f "${PROJECT_DIR}/.eslintrc.yml" ]] || [[ -f "${PROJECT_DIR}/eslint.config.js" ]] || [[ -f "${PROJECT_DIR}/eslint.config.mjs" ]]; then
    add_sensor "eslint" "npx eslint ." "lint" 4 "package.json"
  fi

  # Prettier
  if pkg_has_dep "prettier" || [[ -f "${PROJECT_DIR}/.prettierrc" ]] || [[ -f "${PROJECT_DIR}/.prettierrc.json" ]]; then
    add_sensor "prettier" "npx prettier --check ." "format" 4 "package.json"
  fi
}

# ---------------------------------------------------------------------------
# Rust / Cargo detection
# ---------------------------------------------------------------------------
detect_rust() {
  local cargo="${PROJECT_DIR}/Cargo.toml"
  [[ -f "$cargo" ]] || return 0

  header "Rust project detected (Cargo.toml)"
  DETECTED_TYPES+=("rust")

  add_sensor "cargo-check" "cargo check" "type-check" 1 "Cargo.toml"
  add_sensor "cargo-test"  "cargo test"  "test"       2 "Cargo.toml"

  if has_cmd cargo-clippy || cargo clippy --version &>/dev/null 2>&1; then
    add_sensor "cargo-clippy" "cargo clippy -- -D warnings" "lint" 4 "Cargo.toml"
  fi
}

# ---------------------------------------------------------------------------
# Python detection
# ---------------------------------------------------------------------------
detect_python() {
  local found=false
  local source_file=""

  for f in pyproject.toml setup.py setup.cfg requirements.txt; do
    if [[ -f "${PROJECT_DIR}/${f}" ]]; then
      found=true
      source_file="$f"
      break
    fi
  done
  $found || return 0

  header "Python project detected (${source_file})"
  DETECTED_TYPES+=("python")

  # pytest
  if has_cmd pytest || grep -rq "pytest" "${PROJECT_DIR}/pyproject.toml" 2>/dev/null || [[ -d "${PROJECT_DIR}/tests" ]]; then
    add_sensor "pytest" "python -m pytest" "test" 2 "$source_file"
  fi

  # mypy
  if has_cmd mypy || grep -q "mypy" "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; then
    add_sensor "mypy" "python -m mypy ." "type-check" 1 "$source_file"
  fi

  # ruff
  if has_cmd ruff || grep -q "ruff" "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; then
    add_sensor "ruff" "ruff check ." "lint" 4 "$source_file"
  fi

  # black
  if has_cmd black || grep -q "black" "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; then
    add_sensor "black" "black --check ." "format" 4 "$source_file"
  fi

  # flake8
  if has_cmd flake8 || grep -q "flake8" "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; then
    add_sensor "flake8" "flake8 ." "lint" 4 "$source_file"
  fi
}

# ---------------------------------------------------------------------------
# Go detection
# ---------------------------------------------------------------------------
detect_go() {
  local gomod="${PROJECT_DIR}/go.mod"
  [[ -f "$gomod" ]] || return 0

  header "Go project detected (go.mod)"
  DETECTED_TYPES+=("go")

  add_sensor "go-test" "go test ./..." "test"       2 "go.mod"
  add_sensor "go-vet"  "go vet ./..."  "type-check" 1 "go.mod"

  if has_cmd golangci-lint; then
    add_sensor "golangci-lint" "golangci-lint run" "lint" 4 "go.mod"
  fi
}

# ---------------------------------------------------------------------------
# Makefile detection
# ---------------------------------------------------------------------------
detect_make() {
  local makefile="${PROJECT_DIR}/Makefile"
  [[ -f "$makefile" ]] || return 0

  header "Makefile detected"
  DETECTED_TYPES+=("make")

  if grep -q "^test:" "$makefile" 2>/dev/null; then
    add_sensor "make-test" "make test" "test" 2 "Makefile"
  fi
  if grep -q "^lint:" "$makefile" 2>/dev/null; then
    add_sensor "make-lint" "make lint" "lint" 4 "Makefile"
  fi
  if grep -q "^check:" "$makefile" 2>/dev/null; then
    add_sensor "make-check" "make check" "type-check" 1 "Makefile"
  fi
}

# ---------------------------------------------------------------------------
# Ruby / Bundler detection
# ---------------------------------------------------------------------------
detect_ruby() {
  local gemfile="${PROJECT_DIR}/Gemfile"
  [[ -f "$gemfile" ]] || return 0

  header "Ruby project detected (Gemfile)"
  DETECTED_TYPES+=("ruby")

  if grep -q "rspec" "$gemfile" 2>/dev/null; then
    add_sensor "rspec" "bundle exec rspec" "test" 2 "Gemfile"
  fi

  if grep -q "rubocop" "$gemfile" 2>/dev/null || has_cmd rubocop; then
    add_sensor "rubocop" "bundle exec rubocop" "lint" 4 "Gemfile"
  fi
}

# ---------------------------------------------------------------------------
# Docker Compose detection
# ---------------------------------------------------------------------------
detect_docker() {
  local compose=""
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${PROJECT_DIR}/${f}" ]]; then
      compose="$f"
      break
    fi
  done
  [[ -n "$compose" ]] || return 0

  header "Docker Compose detected (${compose})"
  DETECTED_TYPES+=("docker")

  add_sensor "docker-build" "docker compose build" "build" 1 "$compose"
}

# ---------------------------------------------------------------------------
# Git / pre-commit hooks
# ---------------------------------------------------------------------------
detect_git() {
  if [[ -d "${PROJECT_DIR}/.git" ]]; then
    log "Git repository detected"

    if [[ -f "${PROJECT_DIR}/.pre-commit-config.yaml" ]]; then
      header "Pre-commit hooks detected"
      add_sensor "pre-commit" "pre-commit run --all-files" "lint" 4 ".pre-commit-config.yaml"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Run all detectors
# ---------------------------------------------------------------------------
header "Scanning project: ${PROJECT_DIR}"

detect_node
detect_rust
detect_python
detect_go
detect_make
detect_ruby
detect_docker
detect_git

# ---------------------------------------------------------------------------
# Determine primary project type
# ---------------------------------------------------------------------------
if [[ ${#DETECTED_TYPES[@]} -gt 0 ]]; then
  PROJECT_TYPE="${DETECTED_TYPES[0]}"
else
  PROJECT_TYPE="unknown"
fi

# ---------------------------------------------------------------------------
# Build JSON output
# ---------------------------------------------------------------------------
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo '{'
  echo '  "sensors": ['

  for i in "${!SENSORS[@]}"; do
    echo "${SENSORS[$i]}"
    if [[ $i -lt $(( ${#SENSORS[@]} - 1 )) ]]; then
      # Add comma between entries — trim and append
      echo '    ,'
    fi
  done

  echo '  ],'
  printf '  "detected_at": "%s",\n' "$TIMESTAMP"
  printf '  "project_type": "%s",\n' "$PROJECT_TYPE"

  # detected_types array
  echo -n '  "detected_types": ['
  for i in "${!DETECTED_TYPES[@]}"; do
    [[ $i -gt 0 ]] && echo -n ', '
    echo -n "\"${DETECTED_TYPES[$i]}\""
  done
  echo ']'

  echo '}'
} > "$OUTPUT_FILE"

# If jq is available, re-format for clean output
if has_cmd jq; then
  jq '.' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Detection Complete"
echo ""
printf "${BOLD}  Project type:${RESET}  %s\n" "$PROJECT_TYPE"
printf "${BOLD}  Sensors found:${RESET} %d\n" "${#SENSORS[@]}"
printf "${BOLD}  Output:${RESET}        %s\n" "$OUTPUT_FILE"
echo ""

if [[ ${#SENSORS[@]} -eq 0 ]]; then
  warn "No sensors detected. You can manually add entries to sensors.json."
else
  printf "  ${BOLD}%-20s %-30s %-12s %s${RESET}\n" "NAME" "COMMAND" "TYPE" "PRI"
  printf "  %-20s %-30s %-12s %s\n" "────────────────────" "──────────────────────────────" "────────────" "───"

  if has_cmd jq; then
    jq -r '.sensors[] | "  \(.name)|\(.command)|\(.type)|\(.priority)"' "$OUTPUT_FILE" | \
    while IFS='|' read -r name cmd type pri; do
      printf "  %-20s %-30s %-12s %s\n" "$name" "$cmd" "$type" "$pri"
    done
  else
    ok "Sensors written to ${OUTPUT_FILE}"
  fi
fi

echo ""
