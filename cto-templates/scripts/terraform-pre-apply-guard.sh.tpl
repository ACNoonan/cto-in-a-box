#!/usr/bin/env bash
# =============================================================================
# TERRAFORM PRE-APPLY GUARD
# =============================================================================
# Universal safety checks before any `terraform apply`. Project-specific guards
# (e.g. CloudTrail tag validation, naming-convention checks) should be added as
# numbered sections below.
#
# Usage: invoked by .claude/hooks/terraform-safety.sh OR by CI before apply.
#        Set ENFORCE_DEV_PROMOTION=1 to require {{DEV_BRANCH}} → {{PROD_BRANCH}} fast-forward.
# =============================================================================

set -euo pipefail

fail() {
  echo ""
  echo "ERROR: $1" >&2
  exit 1
}

note() {
  echo "guard: $1"
}

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

note "running terraform pre-apply guardrails"

# 1) Enforce clean working tree (manual applies and CI sanity).
if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is not clean; commit/stash changes before terraform apply"
fi

# 2) Ensure local HEAD is pushed (no local-only commits).
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  read -r behind ahead < <(git rev-list --left-right --count '@{u}...HEAD')
  if (( ahead > 0 )); then
    fail "HEAD has ${ahead} unpushed commit(s); push before terraform apply"
  fi
  note "branch is pushed (ahead=${ahead}, behind=${behind})"
else
  fail "no upstream tracking branch configured for current branch"
fi

# 3) Optional policy: production apply must include latest dev commit.
if [[ "${ENFORCE_DEV_PROMOTION:-0}" == "1" ]]; then
  git fetch origin {{DEV_BRANCH}} {{PROD_BRANCH}} --quiet
  if ! git merge-base --is-ancestor origin/{{DEV_BRANCH}} HEAD; then
    fail "HEAD does not include origin/{{DEV_BRANCH}} tip; promote {{DEV_BRANCH}} -> {{PROD_BRANCH}} with fast-forward before apply"
  fi
  note "{{PROD_BRANCH}} contains origin/{{DEV_BRANCH}} tip"
fi

# 4) PROJECT-SPECIFIC GUARDS — add checks here as you discover landmines.
#
# Each landmine you stub your toe on twice deserves an entry. Examples:
#   - validate that certain Terraform tags don't contain illegal characters
#   - flag known bad patterns in IAM policy JSON
#   - block apply when a specific module changes without a corresponding test run
#
# Pattern (uses ripgrep, requires `brew install ripgrep`):
#
#   if rg -n 'Purpose\s*=\s*".*[()].*"' "terraform/modules/some-module/main.tf" >/dev/null; then
#     fail "invalid Purpose tag characters detected"
#   fi

note "terraform pre-apply guardrails passed"
