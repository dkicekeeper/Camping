// Тексты уведомлений на языке устройства и запрос к APNs.

export type PushKind = "thread_reply" | "friend_request" | "friend_accept";

export type PushRow = {
  outbox_id: number;
  kind: PushKind;
  payload: { actor?: string; username?: string; thread_id?: string; title?: string; snippet?: string };
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
  },
  kk: {
    thread_reply: (p) => ({ title: `Жауап: ${p.title ?? "талқылау"}`, body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_request: (p) => ({ title: "Достық сұрауы", body: `${p.actor} сізді достарға қосқысы келеді` }),
    friend_accept: (p) => ({ title: "Жаңа дос", body: `${p.actor} енді сіздің досыңыз` }),
  },
  en: {
    thread_reply: (p) => ({ title: `Reply: ${p.title ?? "discussion"}`, body: `${p.actor}: ${p.snippet ?? ""}` }),
    friend_request: (p) => ({ title: "Friend request", body: `${p.actor} wants to add you as a friend` }),
    friend_accept: (p) => ({ title: "New friend", body: `${p.actor} is now your friend` }),
  },
};

/// Текст и ссылка для перехода по нажатию (dalada://thread/<id> или dalada://u/<username>).
export function buildMessage(row: PushRow): Message {
  const payload = { ...row.payload, actor: row.payload.actor ?? "Dalada" };
  const { title, body } = (texts[row.language] ?? texts.ru)[row.kind](payload);
  let url: string | undefined;
  if (row.kind === "thread_reply" && row.payload.thread_id) {
    url = `dalada://thread/${row.payload.thread_id}`;
  } else if (row.payload.username) {
    url = `dalada://u/${row.payload.username}`;
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
