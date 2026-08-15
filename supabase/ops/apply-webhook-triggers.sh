#!/usr/bin/env bash
set -euo pipefail

# Applies supabase/ops/webhook_triggers.sql to the configured DATABASE_URL,
# substituting the WEBHOOK_SECRET from api/.env.local or the environment.
# The original template file is never modified and secrets are not written to git.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
API_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
ENV_FILE="$API_DIR/.env.local"
SQL_TEMPLATE="$SCRIPT_DIR/webhook_triggers.sql"

if [ ! -f "$SQL_TEMPLATE" ]; then
  echo "Missing template file: $SQL_TEMPLATE"
  exit 1
fi

# Load .env.local if present; allow environment to take precedence.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

if [ -z "${WEBHOOK_SECRET:-}" ]; then
  echo "WEBHOOK_SECRET is not set in $ENV_FILE or the environment"
  exit 1
fi

DB_URL="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"
if [ -z "$DB_URL" ]; then
  echo "DATABASE_URL or SUPABASE_DB_URL is not set in $ENV_FILE or the environment"
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required but not installed (e.g., 'brew install libpq' on macOS)"
  exit 1
fi

TMP_SQL=$(mktemp "/tmp/webhook_triggers.XXXXXX.sql")
trap 'rm -f "$TMP_SQL"' EXIT

# Literal substitution of the secret; \Q...\E protects any regex special chars.
perl -pe 's/<WEBHOOK_SECRET>/\Q$ENV{WEBHOOK_SECRET}\E/g' "$SQL_TEMPLATE" > "$TMP_SQL"

psql "$DB_URL" -f "$TMP_SQL"

echo "webhook_triggers.sql applied successfully."
