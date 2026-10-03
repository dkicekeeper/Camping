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

Deno.test("проверочное уведомление — без ссылки, на языке устройства", () => {
  const message = buildMessage({ ...reply, kind: "test", language: "en", payload: {} });
  assertEquals(message, { title: "Dalada", body: "Notifications work — this is a test.", url: undefined });
});

Deno.test("комментарий к поездке — ссылка на поездку", () => {
  const message = buildMessage({
    ...reply,
    kind: "comment",
    payload: { actor: "@bob", username: "bob", target_kind: "trip", target_id: "77777777-0000-0000-0000-000000000001", snippet: "Класс!" },
  });
  assertEquals(message, { title: "Новый комментарий", body: "@bob: Класс!", url: "dalada://trip/77777777-0000-0000-0000-000000000001" });
});

Deno.test("комментарий к отчёту — ссылка на комментарии", () => {
  const message = buildMessage({
    ...reply,
    kind: "comment",
    language: "en",
    payload: { actor: "@bob", target_kind: "checkin", target_id: "cccccccc-0000-0000-0000-000000000001", snippet: "Nice" },
  });
  assertEquals(message.title, "New comment");
  assertEquals(message.url, "dalada://comments/checkin/cccccccc-0000-0000-0000-000000000001");
});

Deno.test("пост друга: поездка — на поездку, отчёт — на место", () => {
  const trip = buildMessage({
    ...reply,
    kind: "friend_post",
    language: "kk",
    payload: { actor: "Айгерім", target_kind: "trip", target_id: "77777777-0000-0000-0000-000000000002", title: "Балық аулау" },
  });
  assertEquals(trip, { title: "Достың сапары", body: "Айгерім: Балық аулау", url: "dalada://trip/77777777-0000-0000-0000-000000000002" });
  const report = buildMessage({
    ...reply,
    kind: "friend_post",
    payload: { actor: "Айгерім", target_kind: "checkin", target_id: "cccccccc-0000-0000-0000-000000000002", place_id: "aaaaaaaa-0000-0000-0000-000000000001", place_name: "Озеро S" },
  });
  assertEquals(report, { title: "Отчёт друга", body: "Айгерім — Озеро S", url: "dalada://place/aaaaaaaa-0000-0000-0000-000000000001" });
});

Deno.test("запрет завтра — зона на языке устройства, даты, ссылка на место", () => {
  const payload = {
    zone_ru: "Капшагайское водохранилище",
    zone_kk: "Қапшағай су қоймасы",
    zone_en: "Kapshagay Reservoir",
    starts: "2027-05-10",
    ends: "2027-06-20",
    place_id: "aaaaaaaa-0000-0000-0000-000000000001",
  };
  const ru = buildMessage({ ...reply, kind: "ban_start", payload });
  assertEquals(ru.title, "Завтра запрет: Капшагайское водохранилище");
  assertEquals(ru.body, "С 10.05 по 20.06 рыбалка запрещена. Проверьте правила перед поездкой.");
  assertEquals(ru.url, "dalada://place/aaaaaaaa-0000-0000-0000-000000000001");
  assertEquals(buildMessage({ ...reply, kind: "ban_end", language: "kk", payload }).title, "Тыйым аяқталды: Қапшағай су қоймасы");
  assertEquals(buildMessage({ ...reply, kind: "ban_start", language: "de", payload }).title, "Завтра запрет: Капшагайское водохранилище");
});

Deno.test("новый отзыв в моём месте — оценка, ссылка на место", () => {
  const message = buildMessage({
    ...reply,
    kind: "place_activity",
    language: "en",
    payload: { actor: "@bob", username: "bob", activity: "review", rating: 5, place_id: "aaaaaaaa-0000-0000-0000-000000000001", place_name: "Kapshagay" },
  });
  assertEquals(message, { title: "New review: Kapshagay", body: "@bob: 5 ★", url: "dalada://place/aaaaaaaa-0000-0000-0000-000000000001" });
});

Deno.test("решения модерации: правка — на место, жалоба — без ссылки", () => {
  const suggestion = buildMessage({
    ...reply,
    kind: "moderation",
    payload: { topic: "suggestion", status: "accepted", place_id: "aaaaaaaa-0000-0000-0000-000000000001", place_name: "Коса" },
  });
  assertEquals(suggestion, {
    title: "Правка принята",
    body: "Спасибо! Ваша правка к «Коса» принята.",
    url: "dalada://place/aaaaaaaa-0000-0000-0000-000000000001",
  });
  const report = buildMessage({ ...reply, kind: "moderation", payload: { topic: "report", status: "dismissed" } });
  assertEquals(report, { title: "Жалоба рассмотрена", body: "Нарушений не нашли.", url: undefined });
});
