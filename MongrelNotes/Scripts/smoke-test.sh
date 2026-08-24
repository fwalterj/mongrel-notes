#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MongrelNotes smoke-test.sh
# Runs all three test layers in order, reporting pass/fail per layer.
#
# Usage:
#   ./Scripts/smoke-test.sh           # all layers
#   ./Scripts/smoke-test.sh --spm     # Layer 0 only (SPM unit tests)
#   ./Scripts/smoke-test.sh --build   # Layer 1 only (xcodebuild build)
#   ./Scripts/smoke-test.sh --xctests # Layer 2 only (xcodebuild test)
#
# Requirements:
#   - Xcode (xcodebuild, swift)
#   - xcodegen  (brew install xcodegen)  — only needed when regenerating project
#   Optional:
#   - xcbeautify (brew install xcbeautify) — pretty build output
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/SharedFoundation"
XCODEPROJ="$REPO_ROOT/MongrelNotes.xcodeproj"
SCHEME="MongrelNotes"
DESTINATION="platform=macOS,arch=arm64"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

pass()  { echo -e "${GREEN}${BOLD}✓ PASS${RESET}  $*"; }
fail()  { echo -e "${RED}${BOLD}✗ FAIL${RESET}  $*"; FAILED+=("$*"); }
info()  { echo -e "${YELLOW}▶${RESET} $*"; }
header(){ echo -e "\n${BOLD}══ $* ══${RESET}"; }

FAILED=()
RUN_SPM=false
RUN_BUILD=false
RUN_XCTESTS=false
ALL=true

for arg in "$@"; do
  case $arg in
    --spm)     RUN_SPM=true;     ALL=false ;;
    --build)   RUN_BUILD=true;   ALL=false ;;
    --xctests) RUN_XCTESTS=true; ALL=false ;;
    --help|-h)
      sed -n '3,20p' "$0"
      exit 0
      ;;
  esac
done

$ALL && RUN_SPM=true && RUN_BUILD=true && RUN_XCTESTS=true

# ── Pretty runner ──────────────────────────────────────────────────────────────
run_cmd() {
  local label="$1"; shift
  if command -v xcbeautify &>/dev/null && [[ "$*" == *xcodebuild* ]]; then
    "$@" 2>&1 | xcbeautify && pass "$label" || { fail "$label"; return 1; }
  else
    "$@" && pass "$label" || { fail "$label"; return 1; }
  fi
}

# ── Ensure xcodeproj exists ───────────────────────────────────────────────────
if [[ ! -d "$XCODEPROJ" ]]; then
  info "No .xcodeproj found — running xcodegen…"
  (cd "$REPO_ROOT" && xcodegen generate)
fi

# ── Layer 0: SPM unit tests ───────────────────────────────────────────────────
if $RUN_SPM; then
  header "Layer 0 — SharedFoundation swift test"
  info "swift test --package-path $PACKAGE_DIR"
  run_cmd "SharedFoundation SPM tests" \
    swift test --package-path "$PACKAGE_DIR" || true
fi

# ── Layer 1: xcodebuild compile (no tests) ────────────────────────────────────
if $RUN_BUILD; then
  header "Layer 1 — xcodebuild build (compile only)"
  info "xcodebuild build -scheme $SCHEME …"
  run_cmd "xcodebuild compile" \
    xcodebuild build \
      -project "$XCODEPROJ" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      MN_SKIP_PREBUILD=1 \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
    || true
fi

# ── Layer 2: xcodebuild test (full XCTest run) ────────────────────────────────
if $RUN_XCTESTS; then
  header "Layer 2 — xcodebuild test (MongrelNotesTests)"
  info "xcodebuild test -scheme $SCHEME …"
  run_cmd "MongrelNotesTests XCTest suite" \
    xcodebuild test \
      -project "$XCODEPROJ" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      MN_SKIP_PREBUILD=1 \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
    || true
fi

# ── Summary ────────────────────────────────────────────────────────────────────
header "Summary"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}All layers passed. 🎉${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}${#FAILED[@]} layer(s) failed:${RESET}"
  for f in "${FAILED[@]}"; do
    echo -e "  ${RED}✗${RESET} $f"
  done
  exit 1
fi
