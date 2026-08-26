#!/usr/bin/env bash
# =============================================================================
# sync-onboarding-template.sh
#
# Propagates onboarding.yaml from main to every <team_slug>-onboarding branch.
#
# Usage:
#   ./scripts/sync-onboarding-template.sh [--dry-run] [--branch <branch>]
#
#   --dry-run          Show what would change without committing or pushing.
#   --branch <name>    Sync only the specified branch instead of all of them.
#
# Requirements:
#   - Run from the repo root (or any directory inside the repo).
#   - The working tree must be clean before running.
#   - git and standard POSIX tools.
# =============================================================================

set -euo pipefail

# ── Colour codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=false
ONLY_BRANCH=""

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ; shift ;;
        --branch)   ONLY_BRANCH="$2" ; shift 2 ;;
        -h|--help)
            sed -n '/^# Usage/,/^# Requirements/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo -e "${RED}[ERROR]${NC} Unknown option: $1" >&2 ; exit 1 ;;
    esac
done

# ── Locate repo root ──────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Safety: working tree must be clean ───────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${RED}[ERROR]${NC} Working tree is dirty. Commit or stash your changes first." >&2
    exit 1
fi

# ── Resolve current branch so we can return to it ────────────────────────────
ORIGINAL_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse HEAD)"

# ── Confirm we have the latest onboarding.yaml from main ─────────────────────
echo -e "${BLUE}[INFO]${NC} Fetching origin/main..."
git fetch origin main --quiet
TEMPLATE_SHA="$(git rev-parse origin/main)"
TEMPLATE_CONTENT="$(git show origin/main:onboarding.yaml)"

echo -e "${BLUE}[INFO]${NC} Template: onboarding.yaml @ origin/main (${TEMPLATE_SHA:0:8})"
echo ""

# ── Build list of target branches ─────────────────────────────────────────────
if [[ -n "$ONLY_BRANCH" ]]; then
    TARGET_BRANCHES=("$ONLY_BRANCH")
else
    # All remote branches matching <slug>-onboarding, excluding known non-team
    # branches (rhos-installation-onboarding, test-onboarding, etc.)
    mapfile -t TARGET_BRANCHES < <(
        git branch -r \
          | sed 's|origin/||' \
          | tr -d ' ' \
          | grep -- '-onboarding$' \
          | grep -Ev '^(rhos-installation-onboarding|test-onboarding)$' \
          | sort
    )
fi

if [[ ${#TARGET_BRANCHES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[WARNING]${NC} No target branches found." >&2
    exit 0
fi

echo -e "${BLUE}[INFO]${NC} Target branches (${#TARGET_BRANCHES[@]}):"
for b in "${TARGET_BRANCHES[@]}"; do
    echo "  - $b"
done
echo ""

# ── Counters ─────────────────────────────────────────────────────────────────
UPDATED=0
SKIPPED=0
FAILED=0

# ── Process each branch ───────────────────────────────────────────────────────
for BRANCH in "${TARGET_BRANCHES[@]}"; do

    echo -e "${CYAN}──────────────────────────────────────────────${NC}"
    echo -e "${BLUE}[INFO]${NC} Processing: ${BRANCH}"

    # Fetch latest state of this branch
    if ! git fetch origin "$BRANCH" --quiet 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Branch '$BRANCH' not found on origin — skipping"
        (( FAILED++ )) || true
        continue
    fi

    # Check if onboarding.yaml on this branch already matches main
    CURRENT_CONTENT="$(git show "origin/${BRANCH}:onboarding.yaml" 2>/dev/null || true)"
    if [[ "$CURRENT_CONTENT" == "$TEMPLATE_CONTENT" ]]; then
        echo -e "${GREEN}[SKIP]${NC} onboarding.yaml already up to date on ${BRANCH}"
        (( SKIPPED++ )) || true
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would update onboarding.yaml on ${BRANCH}"
        (( UPDATED++ )) || true
        continue
    fi

    # Check out the branch, update the file, commit, push, return
    git checkout --quiet "$BRANCH"
    git reset --quiet --hard "origin/${BRANCH}"

    echo "$TEMPLATE_CONTENT" > onboarding.yaml
    git add onboarding.yaml

    if git diff --cached --quiet; then
        # Should not happen after the content check above, but guard anyway
        echo -e "${GREEN}[SKIP]${NC} No effective change after checkout on ${BRANCH}"
        (( SKIPPED++ )) || true
    else
        git -c user.name="OnePipeLineCI" -c user.email="onepipelineci@ibm.com" \
            commit -m "chore: sync onboarding.yaml template from main (${TEMPLATE_SHA:0:8})"
        git push origin "${BRANCH}"
        echo -e "${GREEN}[SUCCESS]${NC} Updated and pushed ${BRANCH}"
        (( UPDATED++ )) || true
    fi

done

# ── Return to original branch ─────────────────────────────────────────────────
git checkout --quiet "$ORIGINAL_BRANCH"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Sync Summary${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}Mode     : DRY-RUN (no changes made)${NC}"
fi
echo -e "  ${GREEN}Updated  : ${UPDATED}${NC}"
echo -e "  ${BLUE}Skipped  : ${SKIPPED} (already up to date)${NC}"
[[ $FAILED -gt 0 ]] && echo -e "  ${RED}Failed   : ${FAILED}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"

[[ $FAILED -gt 0 ]] && exit 1 || exit 0
