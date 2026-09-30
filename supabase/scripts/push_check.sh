#!/usr/bin/env bash
# Проверка пушей в облачном проекте (workflow Push check): секреты функции и Vault — только имена,
# устройства — только числа, очередь — виды, попытки и ошибки APNs. Логи открытого репозитория видны
# всем, поэтому ни токенов, ни id людей, ни текстов уведомлений здесь нет.
# С USERNAME кладёт этому человеку проверочное уведомление и ждёт, пока оно уйдёт.
set -euo pipefail

: "${SUPABASE_ACCESS_TOKEN:?нет секрета SUPABASE_ACCESS_TOKEN}"
: "${SUPABASE_PROJECT_REF:?нет секрета SUPABASE_PROJECT_REF}"
REF="$SUPABASE_PROJECT_REF"
USERNAME=$(printf '%s' "${USERNAME:-}" | tr 'A-Z' 'a-z' | tr -d '@[:space:]')

sql() {
  curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$1" '{query: $q}')"
}
table() { jq -r '(.[0] | keys_unsorted | join(" | ")), (.[] | [.[] | tostring] | join(" | "))' 2>/dev/null || cat; }
say() { echo "$1" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"; }

say "### Секреты функции push"
names=$(supabase secrets list --project-ref "$REF" 2>/dev/null | awk -F'|' 'NR>2 {gsub(/ /, "", $1); print $1}')
for name in APNS_KEY_ID APNS_TEAM_ID APNS_PRIVATE_KEY PUSH_WORKER_SECRET; do
  if grep -qx "$name" <<<"$names"; then say "- $name — задан"; else say "- **$name — нет**"; fi
done

say "### Vault"
vault=$(sql "select name from vault.secrets where name in ('push_function_url', 'push_worker_secret') order by name")
for name in push_function_url push_worker_secret; do
  if jq -e --arg n "$name" 'any(.[]; .name == $n)' <<<"$vault" >/dev/null 2>&1; then say "- $name — задан"; else say "- **$name — нет**"; fi
done
url_ok=$(sql "select (decrypted_secret like 'https://' || '$REF' || '.supabase.co/functions/v1/push') as ok from vault.decrypted_secrets where name = 'push_function_url'")
say "- адрес функции указывает на этот проект: $(jq -r '.[0].ok // "нет"' <<<"$url_ok")"

say "### Устройства"
sql "select count(*) as devices, count(distinct user_id) as people, count(*) filter (where environment = 'production') as production, count(*) filter (where environment = 'sandbox') as sandbox from public.devices" | table | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -n "$USERNAME" ]; then
  if ! [[ "$USERNAME" =~ ^[a-z0-9_.]{3,30}$ ]]; then
    say "**username «$USERNAME» — неверный формат**"; exit 1
  fi
  say "### Проверочное уведомление для @$USERNAME"
  devices=$(sql "select count(d.*) as n from public.profiles p left join public.devices d on d.user_id = p.id where p.username = '$USERNAME'" | jq -r '.[0].n // 0')
  say "- телефонов у @$USERNAME: $devices"
  if [ "$devices" = "0" ]; then
    say "- нет зарегистрированных телефонов: откройте приложение (сборка 109+), войдите и разрешите уведомления (Профиль → … → Аккаунт → Уведомления)"
  else
    id=$(sql "insert into private.push_outbox (user_id, kind, payload) select id, 'test', '{}'::jsonb from public.profiles where username = '$USERNAME' returning id" | jq -r '.[0].id')
    sql "select private.push_kick()" > /dev/null
    for _ in $(seq 1 12); do
      sleep 10
      row=$(sql "select sent_at is not null as sent, attempts, coalesce(last_error, '') as error from private.push_outbox where id = $id")
      if [ "$(jq -r '.[0].sent' <<<"$row")" = "true" ] || [ -n "$(jq -r '.[0].error' <<<"$row")" ]; then break; fi
    done
    say "- результат: $(jq -c '.[0]' <<<"$row")"
  fi
fi

say "### Очередь (последние 10)"
sql "select id, kind, attempts, sent_at is not null as sent, left(coalesce(last_error, ''), 60) as error, to_char(created_at, 'MM-DD HH24:MI') as created from private.push_outbox order by id desc limit 10" | table | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

say "### Вызовы функции (pg_net, последние 5)"
sql "select status_code, left(coalesce(content::text, error_msg, ''), 120) as answer, to_char(created, 'MM-DD HH24:MI') as at from net._http_response order by id desc limit 5" | table | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

say "### pg_cron push-worker (последние 3)"
sql "select status, left(coalesce(return_message, ''), 80) as message, to_char(start_time, 'MM-DD HH24:MI') as at from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'push-worker') order by start_time desc limit 3" | table | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
