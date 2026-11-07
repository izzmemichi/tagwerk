#!/bin/sh
# Writes config.js from environment variables (Vercel: Project Settings > Environment Variables).
set -e
: "${SUPABASE_URL:?SUPABASE_URL is not set}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is not set}"
printf 'window.TAGWERK_CONFIG = { url: "%s", key: "%s" };\n' "$SUPABASE_URL" "$SUPABASE_ANON_KEY" > config.js
