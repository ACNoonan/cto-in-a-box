#!/bin/bash
# =============================================================================
# PRISMA CHECK SYNC — Single source of truth for migration sync verification
# =============================================================================
# Checks if a service's database is in sync with its Prisma migrations.
# Used by both local scripts (via tunnel) and CI (CodeBuild with direct access).
#
# Usage:
#   DATABASE_URL=... ./prisma-check-sync.sh [service-dir]
#
# Exit codes:
#   0 — Database is in sync with migrations
#   1 — Database has pending migrations, drift, or errors
# =============================================================================

set -euo pipefail

SERVICE_DIR="${1:-.}"
cd "$SERVICE_DIR"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is not set" >&2
  exit 1
fi

if [ ! -d "prisma/migrations" ]; then
  echo "ERROR: No prisma/migrations directory found in $(pwd)" >&2
  exit 1
fi

SERVICE_NAME=$(basename "$(pwd)")
echo "Checking migration status for ${SERVICE_NAME}..."
echo ""

# Use bunx if available (local dev), fall back to npx (CodeBuild)
if command -v bunx &>/dev/null; then
  PRISMA_CMD="bunx prisma"
elif command -v npx &>/dev/null; then
  PRISMA_VER=$(node -p "const p=require('./package.json');p.dependencies?.prisma||p.devDependencies?.prisma||'latest'" 2>/dev/null || echo "latest")
  PRISMA_CMD="npx prisma@$PRISMA_VER"
else
  echo "ERROR: Neither bunx nor npx found" >&2
  exit 1
fi

# prisma migrate status exits 1 when migrations are pending (Prisma 5+)
set +e
$PRISMA_CMD migrate status
EXIT_CODE=$?
set -e

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "✓ ${SERVICE_NAME} database is in sync with migrations"
else
  echo "✗ ${SERVICE_NAME} database has pending migrations or drift"
fi

exit $EXIT_CODE
