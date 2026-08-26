#!/usr/bin/env bash
# =============================================================================
# extract_bob_verdict.sh
# Extracts the machine-readable verdict from BOB CLI review output.
#
# BOB is instructed to always emit a sentinel block as the very first lines:
#   ##VERDICT_START##
#   VERDICT: APPROVE | NEEDS_REVIEW | BLOCK
#   ##VERDICT_END##
#
# Four extraction layers (in priority order):
#   1. Sentinel block  ##VERDICT_START## / ##VERDICT_END##     (primary)
#   2. Bare line       "VERDICT: <value>"  anywhere            (fallback 1)
#   3. Bold markdown   **APPROVE** / **NEEDS_REVIEW** / **BLOCK** (fallback 2)
#   4. Plain word scan for BLOCK > NEEDS_REVIEW > APPROVE      (fallback 3)
#   5. BOB output missing or empty → BLOCK                     (safety default)
#
# Prints the verdict to stdout.
# Exit codes:
#   0  APPROVE
#   1  NEEDS_REVIEW
#   2  BLOCK
#
# Usage:
#   VERDICT=$(bash extract_bob_verdict.sh bob_review_output.md)
# =============================================================================

set -uo pipefail

BOB_OUTPUT="${1:-bob_review_output.md}"

# ── Safety: missing or empty file ─────────────────────────────────────────────
if [[ ! -f "$BOB_OUTPUT" ]] || [[ ! -s "$BOB_OUTPUT" ]]; then
    echo "BLOCK"
    echo "[VERDICT] BOB output file missing or empty: ${BOB_OUTPUT}" >&2
    exit 2
fi

_emit() {
    # $1 = verdict value, $2 = layer name
    echo "$1"
    echo "[VERDICT] ${2}: ${1}" >&2
    case "$1" in
        APPROVE)      exit 0 ;;
        NEEDS_REVIEW) exit 1 ;;
        BLOCK)        exit 2 ;;
    esac
}

# ── Layer 1: sentinel block ────────────────────────────────────────────────────
V=$(awk '
    /^##VERDICT_START##$/  { in_block=1; next }
    /^##VERDICT_END##$/    { in_block=0; next }
    in_block && /^VERDICT:[[:space:]]*(APPROVE|NEEDS_REVIEW|BLOCK)[[:space:]]*$/ {
        gsub(/^VERDICT:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit
    }
' "$BOB_OUTPUT" 2>/dev/null || true)
[[ "$V" == "APPROVE" || "$V" == "NEEDS_REVIEW" || "$V" == "BLOCK" ]] && _emit "$V" "sentinel block"

# ── Layer 2: bare VERDICT: line ────────────────────────────────────────────────
V=$(grep -oE '^VERDICT:[[:space:]]*(APPROVE|NEEDS_REVIEW|BLOCK)[[:space:]]*$' \
    "$BOB_OUTPUT" 2>/dev/null | head -1 \
    | sed 's/VERDICT:[[:space:]]*//' | tr -d '[:space:]' || true)
[[ "$V" == "APPROVE" || "$V" == "NEEDS_REVIEW" || "$V" == "BLOCK" ]] && _emit "$V" "bare VERDICT line"

# ── Layer 3: bold markdown **VALUE** ──────────────────────────────────────────
V=$(grep -oE '\*\*(APPROVE|NEEDS_REVIEW|BLOCK)\*\*' \
    "$BOB_OUTPUT" 2>/dev/null | head -1 | tr -d '*' || true)
[[ "$V" == "APPROVE" || "$V" == "NEEDS_REVIEW" || "$V" == "BLOCK" ]] && _emit "$V" "bold markdown"

# ── Layer 4: plain word scan (conservative: BLOCK wins) ───────────────────────
grep -qw "BLOCK"        "$BOB_OUTPUT" 2>/dev/null && _emit "BLOCK"        "word scan"
grep -qw "NEEDS_REVIEW" "$BOB_OUTPUT" 2>/dev/null && _emit "NEEDS_REVIEW" "word scan"
grep -qw "APPROVE"      "$BOB_OUTPUT" 2>/dev/null && _emit "APPROVE"      "word scan"

# ── Layer 5: safety default ────────────────────────────────────────────────────
echo "BLOCK"
echo "[VERDICT] All extraction layers failed — defaulting to BLOCK" >&2
echo "[VERDICT] BOB output preview:" >&2
head -10 "$BOB_OUTPUT" >&2
exit 2
