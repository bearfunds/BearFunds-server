#!/usr/bin/env bash
set -euo pipefail

# Applies supabase/ops/webhook_triggers.sql to the configured database,
# substituting WEBHOOK_SECRET and SUPABASE_URL from api/.env.local or the environment.
# The original template file is never modified and secrets are not written to git.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
API_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
ENV_FILE="${DEPLOY_ENV_FILE:-$API_DIR/.env.local}"
SQL_TEMPLATE="$SCRIPT_DIR/webhook_triggers.sql"

if [ ! -f "$SQL_TEMPLATE" ]; then
  echo "Missing template file: $SQL_TEMPLATE"
  exit 1
fi

# Load the env file if present; values already supplied by the environment take precedence.
EXTERNAL_WEBHOOK_SECRET="${WEBHOOK_SECRET-}"
EXTERNAL_SUPABASE_URL="${SUPABASE_URL-}"
EXTERNAL_DATABASE_URL="${DATABASE_URL-}"
EXTERNAL_SUPABASE_DB_URL="${SUPABASE_DB_URL-}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi
[ -n "$EXTERNAL_WEBHOOK_SECRET" ] && WEBHOOK_SECRET="$EXTERNAL_WEBHOOK_SECRET"
[ -n "$EXTERNAL_SUPABASE_URL" ] && SUPABASE_URL="$EXTERNAL_SUPABASE_URL"
[ -n "$EXTERNAL_DATABASE_URL" ] && DATABASE_URL="$EXTERNAL_DATABASE_URL"
[ -n "$EXTERNAL_SUPABASE_DB_URL" ] && SUPABASE_DB_URL="$EXTERNAL_SUPABASE_DB_URL"

if [ -z "${WEBHOOK_SECRET:-}" ]; then
  echo "WEBHOOK_SECRET is not set in $ENV_FILE or the environment"
  exit 1
fi

SUPABASE_URL="${SUPABASE_URL:-}"
if [ -z "$SUPABASE_URL" ] && [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
  SUPABASE_URL="https://${SUPABASE_PROJECT_REF}.supabase.co"
fi
if [ -z "$SUPABASE_URL" ]; then
  echo "SUPABASE_URL or SUPABASE_PROJECT_REF is not set in $ENV_FILE or the environment"
  exit 1
fi
SUPABASE_URL="${SUPABASE_URL%/}"
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

# Literal substitution. \Q...\E belongs on the PATTERN side, where it protects any
# regex special chars in the placeholder. On the replacement side it quotemeta'd the
# VALUE instead, writing "https\:\/\/<ref>\.supabase\.co" into the trigger definition;
# pg_net then rejected it with 'invalid URL ... Bad scheme' and the failure aborted the
# whole auth.users insert, i.e. every sign-up died with "Database error saving new user".
# Interpolating $ENV{...} inserts the value verbatim, so a secret containing special
# characters survives intact.
export WEBHOOK_SECRET SUPABASE_URL
perl -pe 's/\Q<WEBHOOK_SECRET>\E/$ENV{WEBHOOK_SECRET}/g; s/\Q<SUPABASE_URL>\E/$ENV{SUPABASE_URL}/g' "$SQL_TEMPLATE" > "$TMP_SQL"

psql "$DB_URL" -f "$TMP_SQL"

echo "webhook_triggers.sql applied successfully."
