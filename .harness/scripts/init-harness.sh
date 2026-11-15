#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# init-harness.sh — Initialize the harness engineering kit in any project
# Idempotent: safe to re-run without destroying existing data
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
err()   { printf "${RED}✗${RESET}  %s\n" "$*" >&2; }
header(){ printf "\n${BOLD}${CYAN}── %s ──${RESET}\n" "$*"; }

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Initialize the harness engineering kit in a project directory.
Safe to re-run — never overwrites existing memory or decision files.

${BOLD}Options:${RESET}
  -d, --dir DIR       Target project directory (default: current directory)
  -k, --kit-dir DIR   Path to the harness-kit template (default: script's parent)
  -f, --force         Overwrite scripts and templates (but never memory files)
  -h, --help          Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0")
  $(basename "$0") --dir /path/to/my-project
  $(basename "$0") --dir ~/projects/my-app --force
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
PROJECT_DIR="."
KIT_DIR=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)     PROJECT_DIR="$2"; shift 2 ;;
    -k|--kit-dir) KIT_DIR="$2";     shift 2 ;;
    -f|--force)   FORCE=true;       shift   ;;
    -h|--help)    usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If kit dir not specified, assume this script lives inside harness-kit/.harness/scripts/
if [[ -z "$KIT_DIR" ]]; then
  KIT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

header "Initializing Harness in: ${PROJECT_DIR}"

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
create_dir() {
  if [[ -d "$1" ]]; then
    info "Directory exists: $(basename "$1")"
  else
    mkdir -p "$1"
    ok "Created: $1"
  fi
}

header "Creating directory structure"
create_dir "${PROJECT_DIR}/.harness"
create_dir "${PROJECT_DIR}/.harness/memory"
create_dir "${PROJECT_DIR}/.harness/contracts/active"
create_dir "${PROJECT_DIR}/.harness/contracts/completed"
create_dir "${PROJECT_DIR}/.harness/templates"
create_dir "${PROJECT_DIR}/.harness/scripts"
create_dir "${PROJECT_DIR}/.harness/sensor-runs"

# ---------------------------------------------------------------------------
# Copy CLAUDE.md (only if not present or --force)
# ---------------------------------------------------------------------------
header "Setting up CLAUDE.md"
if [[ -f "${PROJECT_DIR}/CLAUDE.md" && "$FORCE" != true ]]; then
  warn "CLAUDE.md already exists — skipping (use --force to overwrite)"
else
  if [[ -f "${KIT_DIR}/CLAUDE.md" ]]; then
    cp "${KIT_DIR}/CLAUDE.md" "${PROJECT_DIR}/CLAUDE.md"
    ok "Installed CLAUDE.md"
  else
    err "Could not find CLAUDE.md template at ${KIT_DIR}/CLAUDE.md"
  fi
fi

# ---------------------------------------------------------------------------
# Copy scripts (always update unless file exists and no --force)
# ---------------------------------------------------------------------------
header "Installing harness scripts"
for script in "${KIT_DIR}/.harness/scripts/"*.sh; do
  [[ -f "$script" ]] || continue
  script_name="$(basename "$script")"
  target="${PROJECT_DIR}/.harness/scripts/${script_name}"

  if [[ -f "$target" && "$FORCE" != true ]]; then
    info "Script exists: ${script_name} (use --force to overwrite)"
  else
    cp "$script" "$target"
    chmod +x "$target"
    ok "Installed script: ${script_name}"
  fi
done

# ---------------------------------------------------------------------------
# Copy templates (always update unless file exists and no --force)
# ---------------------------------------------------------------------------
header "Installing templates"
for template in "${KIT_DIR}/.harness/templates/"*; do
  [[ -f "$template" ]] || continue
  template_name="$(basename "$template")"
  target="${PROJECT_DIR}/.harness/templates/${template_name}"

  if [[ -f "$target" && "$FORCE" != true ]]; then
    info "Template exists: ${template_name}"
  else
    cp "$template" "$target"
    ok "Installed template: ${template_name}"
  fi
done

# ---------------------------------------------------------------------------
# Initialize memory files (NEVER overwrite — these are durable data)
# ---------------------------------------------------------------------------
header "Initializing durable memory files"

init_memory_file() {
  local file="$1"
  local content="$2"
  local target="${PROJECT_DIR}/.harness/memory/${file}"

  if [[ -f "$target" ]]; then
    info "Memory file exists: ${file} (never overwritten)"
  else
    echo "$content" > "$target"
    ok "Created memory file: ${file}"
  fi
}

init_memory_file "decisions.md" "# Architecture Decisions

> This file is durable memory. It persists across sessions.
> Claude reads this at the start of every session.
> Record every significant architecture decision here.

## Format
- **Date**: When it was made
- **Decision**: What was decided
- **Rationale**: Why this choice over alternatives
- **Alternatives Considered**: What else was evaluated
- **Status**: Active | Superseded | Reverted

---

<!-- Decisions go below this line -->"

init_memory_file "bugs.md" "# Known Bugs & Issues

> This file is durable memory. It persists across sessions.
> Claude reads this at the start of every session.

## Format
- **ID**: BUG-001
- **Date Found**: YYYY-MM-DD
- **Description**: What's broken
- **Reproduction Steps**: How to trigger it
- **Workaround**: Temporary fix if any
- **Root Cause**: Once identified
- **Status**: Open | Working Around | Fixed | Won't Fix

---

<!-- Bugs go below this line -->"

init_memory_file "preferences.md" "# User & Team Preferences

> This file is durable memory. It persists across sessions.
> Claude reads this at the start of every session.

## Coding Style
- **Language**:
- **Formatting**:
- **Naming Conventions**:
- **Import Style**:

## Workflow Preferences
- **Testing**:
- **Git**:
- **Documentation**:
- **Error Handling**:

## Communication Preferences
- **Verbosity**: [concise | detailed | minimal]
- **Explanations**: [always | only when asked | never]
- **Code Comments**: [liberal | minimal | doc-strings only]

---

<!-- Additional preferences go below this line -->"

init_memory_file "progress.md" "# Project Progress

> This file is durable memory. It persists across sessions.
> Claude reads this at the start of every session.

## Current State
**Last Updated**: $(date +%Y-%m-%d)
**Active Contract**: none
**Overall Status**: Project initialized with harness engineering kit

## Completed
| Date | Task | Contract | Sensor Evidence |
|------|------|----------|----------------|

## In Progress
| Task | Started | Blockers | Next Step |
|------|---------|----------|-----------|

## Backlog

---

<!-- Progress updates go below this line -->"

# ---------------------------------------------------------------------------
# Run sensor detection
# ---------------------------------------------------------------------------
header "Detecting sensors"
DETECT_SCRIPT="${PROJECT_DIR}/.harness/scripts/detect-sensors.sh"
if [[ -x "$DETECT_SCRIPT" ]]; then
  bash "$DETECT_SCRIPT" --dir "$PROJECT_DIR" || warn "Sensor detection encountered issues (non-fatal)"
else
  warn "detect-sensors.sh not found or not executable"
fi

# ---------------------------------------------------------------------------
# Generate project map
# ---------------------------------------------------------------------------
header "Generating project map"
MAP_SCRIPT="${PROJECT_DIR}/.harness/scripts/generate-map.sh"
if [[ -x "$MAP_SCRIPT" ]]; then
  bash "$MAP_SCRIPT" --dir "$PROJECT_DIR" || warn "Map generation encountered issues (non-fatal)"
else
  warn "generate-map.sh not found — creating placeholder map"
  cat > "${PROJECT_DIR}/.harness/map.md" <<MAPEOF
# Project Map

> Compact index of the project structure.
> Run \`.harness/scripts/generate-map.sh\` to regenerate.

**Last Generated**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Project Root**: ${PROJECT_DIR}

## Directory Structure
\`\`\`
$(find "$PROJECT_DIR" -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/.harness/*' -not -name '.DS_Store' | head -60 | sed "s|${PROJECT_DIR}|.|g" | sort)
\`\`\`

## Key Files
| File | Purpose | Last Modified |
|------|---------|---------------|
| CLAUDE.md | Harness operating manual | $(date +%Y-%m-%d) |

> Re-run \`.harness/scripts/generate-map.sh\` for a full map.
MAPEOF
  ok "Created placeholder map"
fi

# ---------------------------------------------------------------------------
# Add .harness to .gitignore (sensor runs and logs, not config)
# ---------------------------------------------------------------------------
header "Configuring .gitignore"
GITIGNORE="${PROJECT_DIR}/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if ! grep -q ".harness/sensor-runs/" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Harness engineering kit - ephemeral data" >> "$GITIGNORE"
    echo ".harness/sensor-runs/" >> "$GITIGNORE"
    ok "Added .harness/sensor-runs/ to .gitignore"
  else
    info ".gitignore already configured"
  fi
else
  cat > "$GITIGNORE" <<GIEOF
# Harness engineering kit - ephemeral data
.harness/sensor-runs/
GIEOF
  ok "Created .gitignore with harness exclusions"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Harness Initialization Complete"
echo ""
printf "${BOLD}  Project:${RESET}     %s\n" "$PROJECT_DIR"
printf "${BOLD}  CLAUDE.md:${RESET}   %s\n" "$([ -f "${PROJECT_DIR}/CLAUDE.md" ] && echo "✓ installed" || echo "✗ missing")"
printf "${BOLD}  Memory:${RESET}      %s\n" "$(ls "${PROJECT_DIR}/.harness/memory/" 2>/dev/null | wc -l | tr -d ' ') files"
printf "${BOLD}  Sensors:${RESET}     %s\n" "$([ -f "${PROJECT_DIR}/.harness/sensors.json" ] && echo "✓ configured" || echo "⚠ not detected")"
printf "${BOLD}  Map:${RESET}         %s\n" "$([ -f "${PROJECT_DIR}/.harness/map.md" ] && echo "✓ generated" || echo "⚠ not generated")"
echo ""
printf "${GREEN}${BOLD}  Ready to go!${RESET} Open Claude Code in this directory and it will\n"
printf "  auto-load CLAUDE.md and operate under harness rules.\n"
echo ""
printf "${CYAN}  Next steps:${RESET}\n"
printf "    1. Review and customize ${BOLD}.harness/memory/preferences.md${RESET}\n"
printf "    2. Start a task: ${BOLD}.harness/scripts/new-contract.sh \"your task description\"${RESET}\n"
printf "    3. Claude will auto-generate contracts, run sensors, and maintain memory\n"
echo ""
