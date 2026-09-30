import { assertEquals } from "jsr:@std/assert@1";
import { apnsRequest, buildMessage, type PushRow } from "./message.ts";

const reply: PushRow = {
  outbox_id: 1,
  kind: "thread_reply",
  payload: { actor: "@bob", username: "bob", thread_id: "dddddddd-0000-0000-0000-000000000001", title: "Дорога", snippet: "Через мост" },
  token: "ab".repeat(32),
  environment: "production",
  language: "ru",
};

Deno.test("ответ в обсуждении — текст и ссылка на обсуждение", () => {
  assertEquals(buildMessage(reply), {
    title: "Ответ: Дорога",
    body: "@bob: Через мост",
    url: "dalada://thread/dddddddd-0000-0000-0000-000000000001",
  });
});

Deno.test("запрос в друзья на казахском — ссылка на профиль", () => {
  const message = buildMessage({ ...reply, kind: "friend_request", language: "kk", payload: { actor: "Айгерім", username: "aigerim" } });
  assertEquals(message.body, "Айгерім сізді достарға қосқысы келеді");
  assertEquals(message.url, "dalada://u/aigerim");
});

Deno.test("незнакомый язык — русский", () => {
  assertEquals(buildMessage({ ...reply, kind: "friend_accept", language: "de" }).title, "Новый друг");
});

Deno.test("запрос к APNs: окружение, тема, тело", () => {
  const request = apnsRequest({ ...reply, environment: "sandbox" }, buildMessage(reply), "app.dalada.ios", 1000);
  assertEquals(request.url, `https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
  assertEquals(request.headers["apns-topic"], "app.dalada.ios");
  assertEquals(request.headers["apns-expiration"], "87400");
  assertEquals(JSON.parse(request.body).aps.alert.title, "Ответ: Дорога");
  assertEquals(JSON.parse(request.body).url, "dalada://thread/dddddddd-0000-0000-0000-000000000001");
});
