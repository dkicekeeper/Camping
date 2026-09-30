// Отправка пуш-уведомлений в APNs (M6d).
//
// Раз в минуту база вызывает функцию (pg_cron → private.push_kick → pg_net) с заголовком
// x-push-secret. Функция забирает пачку из очереди (RPC push_claim), отправляет каждое уведомление
// на все телефоны получателя и отчитывается (RPC push_finish): доставленные, ошибки и токены,
// которые APNs больше не принимает.
//
// Секреты функции (Supabase → Edge Functions → Secrets): PUSH_WORKER_SECRET (тот же, что в Vault),
// APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (содержимое .p8), APNS_TOPIC (по умолчанию app.dalada.ios).
// SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY Supabase подставляет сам.

import { createClient } from "npm:@supabase/supabase-js@2";
import { apnsRequest, buildMessage, type PushRow } from "./message.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing secret ${name}`);
  return value;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// Токен APNs действует час; обновлять не чаще раза в 20 минут — держим 50 минут.
let cachedToken: { value: string; issuedAt: number } | null = null;

async function apnsToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.issuedAt < 50 * 60) return cachedToken.value;
  const encode = (data: Uint8Array) =>
    btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const text = (value: unknown) => encode(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${text({ alg: "ES256", kid: env("APNS_KEY_ID") })}.${text({ iss: env("APNS_TEAM_ID"), iat: now })}`;
  const pem = env("APNS_PRIVATE_KEY").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)),
  );
  cachedToken = { value: `${unsigned}.${encode(signature)}`, issuedAt: now };
  return cachedToken.value;
}

type Result = { ok: true } | { ok: false; dead: boolean; reason: string };

// Токен не подходит этому приложению или устройство удалило приложение — больше не отправляем.
const deadReasons = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

async function send(row: PushRow, jwt: string, topic: string): Promise<Result> {
  const request = apnsRequest(row, buildMessage(row), topic, Math.floor(Date.now() / 1000));
  try {
    const response = await fetch(request.url, {
      method: "POST",
      headers: { ...request.headers, authorization: `bearer ${jwt}` },
      body: request.body,
    });
    if (response.ok) return { ok: true };
    const reason = ((await response.json().catch(() => ({}))) as { reason?: string }).reason ?? `HTTP ${response.status}`;
    return { ok: false, dead: response.status === 410 || deadReasons.has(reason), reason };
  } catch (error) {
    return { ok: false, dead: false, reason: String(error).slice(0, 200) };
  }
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("PUSH_WORKER_SECRET");
  if (!secret || request.headers.get("x-push-secret") !== secret) {
    return json({ error: "forbidden" }, 403);
  }

  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  const { data, error } = await supabase.rpc("push_claim", { p_limit: 200 });
  if (error) return json({ error: error.message }, 500);
  const rows = (data ?? []) as PushRow[];
  if (rows.length === 0) return json({ sent: 0 });

  const jwt = await apnsToken();
  const topic = Deno.env.get("APNS_TOPIC") ?? "app.dalada.ios";
  const results = await Promise.all(rows.map(async (row) => ({ row, result: await send(row, jwt, topic) })));

  // Уведомление доставлено, если дошло хотя бы на один телефон получателя.
  const sent = new Set<number>();
  const dead = new Set<string>();
  const errors: Record<string, string> = {};
  for (const { row, result } of results) {
    if (result.ok) {
      sent.add(row.outbox_id);
    } else {
      if (result.dead) dead.add(row.token);
      errors[String(row.outbox_id)] = result.reason;
    }
  }
  for (const id of sent) delete errors[String(id)];

  const finish = await supabase.rpc("push_finish", {
    p_sent: [...sent],
    p_dead_tokens: [...dead],
    p_errors: errors,
  });
  if (finish.error) return json({ error: finish.error.message }, 500);
  return json({ sent: sent.size, failed: Object.keys(errors).length, removedTokens: dead.size });
});
