#!/usr/bin/env bash
# Проверяет ключи R2 (без вывода значений) и передаёт rclone адрес и ключи через $GITHUB_ENV.
# Account ID — не секрет, он в map/config.json (R2 → Overview → Account Details).
set -euo pipefail

trim() { printf '%s' "$1" | tr -d '[:space:]'; }
account=$(python3 -c "import json; print(json.load(open('map/config.json'))['account_id'])")
key_id=$(trim "${R2_ACCESS_KEY_ID:-}")
secret=$(trim "${R2_SECRET_ACCESS_KEY:-}")

problems=()
[[ "$account" =~ ^[0-9a-f]{32}$ ]] || problems+=("map/config.json: account_id — 32 символа 0-9a-f")
[[ "$key_id" =~ ^[0-9a-fA-F]{32}$ ]] || problems+=("R2_ACCESS_KEY_ID: ждём 32 символа 0-9a-f, сейчас ${#key_id} символов")
[[ "$secret" =~ ^[0-9a-fA-F]{64}$ ]] || problems+=("R2_SECRET_ACCESS_KEY: ждём 64 символа 0-9a-f, сейчас ${#secret} символов")

endpoint="https://$account.r2.cloudflarestorage.com"
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 "$endpoint" || true)
# Без подписи R2 отвечает 400/403; 000 — не удалось даже установить соединение (чужой или неверный id).
if [ "$code" = "000" ]; then
  problems+=("по адресу S3 API аккаунта нет ответа (TLS) — проверьте account_id в map/config.json")
fi

if [ ${#problems[@]} -gt 0 ]; then
  for p in "${problems[@]}"; do echo "::error::$p"; done
  echo "::error::Секреты — Settings → Secrets and variables → Actions (map/README.md)."
  exit 1
fi

{
  echo "RCLONE_CONFIG_R2_ENDPOINT=$endpoint"
  echo "RCLONE_CONFIG_R2_ACCESS_KEY_ID=$key_id"
  echo "RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$secret"
} >> "$GITHUB_ENV"
echo "R2: ключи в порядке, S3 API отвечает (HTTP $code)"
