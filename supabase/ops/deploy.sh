#!/usr/bin/env bash
set -euo pipefail

OPS_DIR=$(cd "$(dirname "$0")" && pwd)
API_DIR=$(cd "$OPS_DIR/../.." && pwd)
ENV_FILE="${DEPLOY_ENV_FILE:-$API_DIR/.env.local}"

# Load local deployment inputs without changing tracked files.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF to the target Supabase project ref}"
: "${WEBHOOK_SECRET:?Set WEBHOOK_SECRET to the value already configured for the target project}"

SUPABASE_URL="${SUPABASE_URL:-https://${SUPABASE_PROJECT_REF}.supabase.co}"
SUPABASE_URL="${SUPABASE_URL%/}"
DB_URL="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"
: "${DB_URL:?Set DATABASE_URL or SUPABASE_DB_URL to the target database connection string}"

for command in supabase psql perl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command"
    exit 1
  fi
done

export SUPABASE_URL WEBHOOK_SECRET DATABASE_URL="$DB_URL"

echo "Applying database migrations to $SUPABASE_PROJECT_REF..."
supabase db push --db-url "$DB_URL"

for function in api parse-receipt send-welcome-email send-feedback-notification; do
  echo "Deploying Edge Function: $function"
  supabase functions deploy "$function" --project-ref "$SUPABASE_PROJECT_REF"
done

echo "Configuring database webhook triggers..."
bash "$OPS_DIR/apply-webhook-triggers.sh"

echo "Supabase deployment completed for $SUPABASE_PROJECT_REF."
