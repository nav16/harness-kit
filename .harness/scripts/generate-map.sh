#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# generate-map.sh — Generate a compact project map for Claude's context
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
warn()  { printf "${YELLOW}⚠${RESET}  %s\n" "$*"; }
header(){ printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Generate a compact project map at .harness/map.md

${BOLD}Options:${RESET}
  -d, --dir DIR       Project directory to scan (default: current directory)
  -o, --output FILE   Output path (default: .harness/map.md)
  -m, --max-depth N   Max directory depth (default: 4)
  -h, --help          Show this help message
EOF
  exit 0
}

PROJECT_DIR="."
OUTPUT_FILE=""
MAX_DEPTH=4

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)       PROJECT_DIR="$2"; shift 2 ;;
    -o|--output)    OUTPUT_FILE="$2";  shift 2 ;;
    -m|--max-depth) MAX_DEPTH="$2";    shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="${PROJECT_DIR}/.harness/map.md"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# ---------------------------------------------------------------------------
# Exclusion patterns
# ---------------------------------------------------------------------------
EXCLUDES=(
  "node_modules" ".git" "__pycache__" ".venv" "venv" ".env"
  "target" "dist" "build" ".next" ".nuxt" ".output"
  ".harness" ".DS_Store" ".idea" ".vscode" "coverage"
  ".pytest_cache" ".mypy_cache" ".ruff_cache" "*.pyc"
  ".tox" "egg-info" ".eggs"
)

build_find_excludes() {
  local result=""
  for pattern in "${EXCLUDES[@]}"; do
    result+=" -name '${pattern}' -prune -o"
  done
  echo "$result"
}

# ---------------------------------------------------------------------------
# Detect project type and entry points
# ---------------------------------------------------------------------------
detect_project_type() {
  local types=()
  local entry=""

  if [[ -f "${PROJECT_DIR}/package.json" ]]; then
    types+=("node")
    if command -v jq &>/dev/null; then
      entry=$(jq -r '.main // .module // "index.js"' "${PROJECT_DIR}/package.json" 2>/dev/null || echo "")
    fi
  fi
  [[ -f "${PROJECT_DIR}/Cargo.toml" ]] && types+=("rust")
  [[ -f "${PROJECT_DIR}/go.mod" ]] && types+=("go")
  [[ -f "${PROJECT_DIR}/pyproject.toml" || -f "${PROJECT_DIR}/setup.py" ]] && types+=("python")
  [[ -f "${PROJECT_DIR}/Gemfile" ]] && types+=("ruby")
  [[ -f "${PROJECT_DIR}/Makefile" ]] && types+=("make")

  if [[ ${#types[@]} -eq 0 ]]; then
    echo "unknown|unknown"
  else
    local joined
    joined=$(IFS='+'; echo "${types[*]}")
    echo "${joined}|${entry:-unknown}"
  fi
}

# ---------------------------------------------------------------------------
# Generate tree structure
# ---------------------------------------------------------------------------
generate_tree() {
  if command -v tree &>/dev/null; then
    local exclude_pattern
    exclude_pattern=$(IFS='|'; echo "${EXCLUDES[*]}")
    tree "$PROJECT_DIR" -L "$MAX_DEPTH" --charset utf-8 -I "$exclude_pattern" --dirsfirst -F 2>/dev/null | head -100
  else
    # Fallback: use find
    eval "find '$PROJECT_DIR' -maxdepth $MAX_DEPTH \
      $(build_find_excludes) \
      -print" 2>/dev/null | \
      sed "s|${PROJECT_DIR}|.|g" | \
      sort | \
      head -100
  fi
}

# ---------------------------------------------------------------------------
# Gather key files with descriptions
# ---------------------------------------------------------------------------
gather_key_files() {
  local files=()

  # Configuration files
  for f in package.json tsconfig.json Cargo.toml go.mod pyproject.toml \
           Makefile Dockerfile docker-compose.yml .env.example \
           CLAUDE.md README.md; do
    if [[ -f "${PROJECT_DIR}/${f}" ]]; then
      local size modified
      size=$(wc -c < "${PROJECT_DIR}/${f}" 2>/dev/null | tr -d ' ')
      modified=$(stat -f "%Sm" -t "%Y-%m-%d" "${PROJECT_DIR}/${f}" 2>/dev/null || stat -c "%y" "${PROJECT_DIR}/${f}" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
      local desc=""
      case "$f" in
        package.json)       desc="Node.js project manifest and dependencies" ;;
        tsconfig.json)      desc="TypeScript compiler configuration" ;;
        Cargo.toml)         desc="Rust project manifest and dependencies" ;;
        go.mod)             desc="Go module definition" ;;
        pyproject.toml)     desc="Python project configuration" ;;
        Makefile)           desc="Build automation rules" ;;
        Dockerfile)         desc="Container image definition" ;;
        docker-compose.yml) desc="Multi-container orchestration" ;;
        .env.example)       desc="Environment variable template" ;;
        CLAUDE.md)          desc="Harness operating manual for Claude" ;;
        README.md)          desc="Project documentation" ;;
        *)                  desc="Configuration" ;;
      esac
      echo "| \`${f}\` | ${desc} | ${modified} | ${size}B |"
    fi
  done
}

# ---------------------------------------------------------------------------
# Gather source directories
# ---------------------------------------------------------------------------
gather_source_dirs() {
  local src_dirs=("src" "lib" "app" "pages" "components" "api" "cmd" "pkg"
                  "internal" "tests" "test" "spec" "__tests__" "scripts"
                  "utils" "helpers" "hooks" "services" "models" "routes"
                  "controllers" "middleware" "config")

  for dir in "${src_dirs[@]}"; do
    if [[ -d "${PROJECT_DIR}/${dir}" ]]; then
      local count
      count=$(find "${PROJECT_DIR}/${dir}" -type f -not -name '*.pyc' -not -name '.DS_Store' 2>/dev/null | wc -l | tr -d ' ')
      echo "| \`${dir}/\` | ${count} files |"
    fi
  done
}

# ---------------------------------------------------------------------------
# Build the map
# ---------------------------------------------------------------------------
header "Generating project map for: ${PROJECT_NAME}"

TYPE_ENTRY=$(detect_project_type)
PROJECT_TYPE="${TYPE_ENTRY%%|*}"
ENTRY_POINT="${TYPE_ENTRY##*|}"

TREE_OUTPUT=$(generate_tree)
KEY_FILES=$(gather_key_files)
SOURCE_DIRS=$(gather_source_dirs)

cat > "$OUTPUT_FILE" <<MAPEOF
# Project Map: ${PROJECT_NAME}

> Compact index of the project structure.
> Claude reads this to locate files without loading everything into context.
> Regenerate with: \`.harness/scripts/generate-map.sh\`

**Last Generated**: ${TIMESTAMP}
**Project Type**: ${PROJECT_TYPE}
**Entry Point**: \`${ENTRY_POINT}\`
**Project Root**: \`${PROJECT_DIR}\`

---

## Directory Structure

\`\`\`
${TREE_OUTPUT}
\`\`\`

---

## Key Files

| File | Purpose | Last Modified | Size |
|------|---------|---------------|------|
${KEY_FILES}

---

## Source Directories

| Directory | Contents |
|-----------|----------|
${SOURCE_DIRS}

---

## Notes

- This map is auto-generated. Update it after major structural changes.
- Claude should use this to locate files, then read only the needed file.
- Do NOT dump file contents into chat — use the map to navigate.
MAPEOF

ok "Project map written to: ${OUTPUT_FILE}"
info "$(wc -l < "$OUTPUT_FILE" | tr -d ' ') lines"
