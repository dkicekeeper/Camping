// Тексты уведомлений на языке устройства и запрос к APNs.

export type PushKind = "thread_reply" | "friend_request" | "friend_accept" | "comment" | "friend_post" | "test";

export type PushRow = {
  outbox_id: number;
  kind: PushKind;
  payload: {
    actor?: string;
    username?: string;
    thread_id?: string;
    title?: string;
    snippet?: string;
    // Комментарий и пост друга: что за пост (trip, checkin, review) и его id; у отчёта — место.
    target_kind?: string;
    target_id?: string;
    place_id?: string;
    place_name?: string;
  };
  token: string;
  environment: "sandbox" | "production";
  language: string;
};

export type Message = { title: string; body: string; url?: string };

type Payload = PushRow["payload"];

const texts: Record<string, Record<PushKind, (p: Payload) => { title: string; body: string }>> = {
  ru: {
    thread_reply: (p) => ({ title: `Ответ: ${p.title ?? "обсуждение"}`, body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_request: (p) => ({ title: "Запрос в друзья", body: `${p.actor} хочет добавить вас в друзья` }),
    friend_accept: (p) => ({ title: "Новый друг", body: `${p.actor} теперь у вас в друзьях` }),
    comment: (p) => ({ title: "Новый комментарий", body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_post: (p) =>
      p.target_kind === "trip"
        ? { title: "Поездка друга", body: `${p.actor}: ${p.title ?? "новая поездка"}` }
        : { title: "Отчёт друга", body: `${p.actor} — ${p.place_name ?? "новый отчёт"}` },
    test: () => ({ title: "Dalada", body: "Уведомления работают — это проверка." }),
  },
  kk: {
    thread_reply: (p) => ({ title: `Жауап: ${p.title ?? "талқылау"}`, body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_request: (p) => ({ title: "Достық сұрауы", body: `${p.actor} сізді достарға қосқысы келеді` }),
    friend_accept: (p) => ({ title: "Жаңа дос", body: `${p.actor} енді сіздің досыңыз` }),
    comment: (p) => ({ title: "Жаңа түсініктеме", body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_post: (p) =>
      p.target_kind === "trip"
        ? { title: "Достың сапары", body: `${p.actor}: ${p.title ?? "жаңа сапар"}` }
        : { title: "Достың есебі", body: `${p.actor} — ${p.place_name ?? "жаңа есеп"}` },
    test: () => ({ title: "Dalada", body: "Хабарландырулар жұмыс істейді — бұл тексеру." }),
  },
  en: {
    thread_reply: (p) => ({ title: `Reply: ${p.title ?? "discussion"}`, body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_request: (p) => ({ title: "Friend request", body: `${p.actor} wants to add you as a friend` }),
    friend_accept: (p) => ({ title: "New friend", body: `${p.actor} is now your friend` }),
    comment: (p) => ({ title: "New comment", body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_post: (p) =>
      p.target_kind === "trip"
        ? { title: "Friend’s trip", body: `${p.actor}: ${p.title ?? "a new trip"}` }
        : { title: "Friend’s report", body: `${p.actor} — ${p.place_name ?? "a new report"}` },
    test: () => ({ title: "Dalada", body: "Notifications work — this is a test." }),
  },
};

/// Текст и ссылка для перехода по нажатию: обсуждение (dalada://thread/<id>), поездка
/// (dalada://trip/<id>), место отчёта друга (dalada://place/<id>), комментарии к отчёту или отзыву
/// (dalada://comments/<checkin|review>/<id>), иначе профиль автора (dalada://u/<username>).
export function buildMessage(row: PushRow): Message {
  const p = row.payload;
  const payload = { ...p, actor: p.actor ?? "Dalada" };
  const { title, body } = (texts[row.language] ?? texts.ru)[row.kind](payload);
  let url: string | undefined;
  if (row.kind === "thread_reply" && p.thread_id) {
    url = `dalada://thread/${p.thread_id}`;
  } else if ((row.kind === "comment" || row.kind === "friend_post") && p.target_kind === "trip" && p.target_id) {
    url = `dalada://trip/${p.target_id}`;
  } else if (row.kind === "friend_post" && p.place_id) {
    url = `dalada://place/${p.place_id}`;
  } else if (row.kind === "comment" && p.target_kind && p.target_id) {
    url = `dalada://comments/${p.target_kind}/${p.target_id}`;
  } else if (p.username) {
    url = `dalada://u/${p.username}`;
  }
  return { title, body, url };
}

export function apnsRequest(row: PushRow, message: Message, topic: string, now: number) {
  const host = row.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  return {
    url: `https://${host}/3/device/${row.token}`,
    headers: {
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(now + 24 * 60 * 60),
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title: message.title, body: message.body }, sound: "default", "thread-id": row.kind },
      ...(message.url ? { url: message.url } : {}),
    }),
  };
}
