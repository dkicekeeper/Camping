// Тексты уведомлений на языке устройства и запрос к APNs.

export type PushKind =
  | "thread_reply"
  | "friend_request"
  | "friend_accept"
  | "comment"
  | "friend_post"
  | "ban_start"
  | "ban_end"
  | "place_activity"
  | "moderation"
  | "test";

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
    // Запрет: зона на трёх языках и даты (ГГГГ-ММ-ДД).
    zone_ru?: string;
    zone_kk?: string;
    zone_en?: string;
    starts?: string;
    ends?: string;
    // Новое в вашем месте: checkin или review; оценка отзыва.
    activity?: string;
    rating?: number;
    // Решение модерации: suggestion или report; accepted, rejected, resolved, dismissed.
    topic?: string;
    status?: string;
  };
  token: string;
  environment: "sandbox" | "production";
  language: string;
};

export type Message = { title: string; body: string; url?: string };

type Payload = PushRow["payload"] & { zone?: string };

/// «2027-05-10» → «10.05».
function day(value?: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value ?? "");
  return match ? `${match[3]}.${match[2]}` : "";
}

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
    ban_start: (p) => ({
      title: `Завтра запрет: ${p.zone}`,
      body: `С ${day(p.starts)} по ${day(p.ends)} рыбалка запрещена. Проверьте правила перед поездкой.`,
    }),
    ban_end: (p) => ({ title: `Запрет закончился: ${p.zone}`, body: `Рыбалка снова разрешена — запрет действовал до ${day(p.ends)}.` }),
    place_activity: (p) =>
      p.activity === "review"
        ? { title: `Новый отзыв: ${p.place_name ?? ""}`, body: `${p.actor}: ${p.rating ?? ""} ★` }
        : { title: `Новый отчёт: ${p.place_name ?? ""}`, body: `${p.actor} — новый отчёт в вашем месте` },
    moderation: (p) =>
      p.topic === "suggestion"
        ? p.status === "accepted"
          ? { title: "Правка принята", body: `Спасибо! Ваша правка к «${p.place_name ?? ""}» принята.` }
          : { title: "Правка не принята", body: `Редакция не приняла правку к «${p.place_name ?? ""}».` }
        : p.status === "resolved"
        ? { title: "Жалоба рассмотрена", body: "Спасибо! Мы приняли меры." }
        : { title: "Жалоба рассмотрена", body: "Нарушений не нашли." },
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
    ban_start: (p) => ({
      title: `Ертең тыйым: ${p.zone}`,
      body: `${day(p.starts)}–${day(p.ends)} аралығында балық аулауға тыйым салынады. Сапар алдында ережелерді тексеріңіз.`,
    }),
    ban_end: (p) => ({ title: `Тыйым аяқталды: ${p.zone}`, body: `Балық аулауға қайта рұқсат — тыйым ${day(p.ends)} дейін болды.` }),
    place_activity: (p) =>
      p.activity === "review"
        ? { title: `Жаңа пікір: ${p.place_name ?? ""}`, body: `${p.actor}: ${p.rating ?? ""} ★` }
        : { title: `Жаңа есеп: ${p.place_name ?? ""}`, body: `${p.actor} — сіздің орныңызда жаңа есеп` },
    moderation: (p) =>
      p.topic === "suggestion"
        ? p.status === "accepted"
          ? { title: "Түзету қабылданды", body: `Рақмет! «${p.place_name ?? ""}» орнына түзетуіңіз қабылданды.` }
          : { title: "Түзету қабылданбады", body: `Редакция «${p.place_name ?? ""}» орнына түзетуді қабылдамады.` }
        : p.status === "resolved"
        ? { title: "Шағым қаралды", body: "Рақмет! Шара қолданылды." }
        : { title: "Шағым қаралды", body: "Бұзушылық табылмады." },
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
    ban_start: (p) => ({
      title: `Ban from tomorrow: ${p.zone}`,
      body: `Fishing is banned from ${day(p.starts)} to ${day(p.ends)}. Check the rules before your trip.`,
    }),
    ban_end: (p) => ({ title: `Ban is over: ${p.zone}`, body: `Fishing is allowed again — the ban lasted until ${day(p.ends)}.` }),
    place_activity: (p) =>
      p.activity === "review"
        ? { title: `New review: ${p.place_name ?? ""}`, body: `${p.actor}: ${p.rating ?? ""} ★` }
        : { title: `New report: ${p.place_name ?? ""}`, body: `${p.actor} posted a report at your place` },
    moderation: (p) =>
      p.topic === "suggestion"
        ? p.status === "accepted"
          ? { title: "Edit accepted", body: `Thanks! Your edit to “${p.place_name ?? ""}” was accepted.` }
          : { title: "Edit not accepted", body: `The editors didn’t accept your edit to “${p.place_name ?? ""}”.` }
        : p.status === "resolved"
        ? { title: "Report reviewed", body: "Thanks! We took action." }
        : { title: "Report reviewed", body: "We found no violation." },
    test: () => ({ title: "Dalada", body: "Notifications work — this is a test." }),
  },
};

/// Текст и ссылка для перехода по нажатию: обсуждение (dalada://thread/<id>), поездка
/// (dalada://trip/<id>), место отчёта друга (dalada://place/<id>), комментарии к отчёту или отзыву
/// (dalada://comments/<checkin|review>/<id>), иначе профиль автора (dalada://u/<username>).
export function buildMessage(row: PushRow): Message {
  const p = row.payload;
  const language = texts[row.language] ? row.language : "ru";
  const zones: Record<string, string | undefined> = { ru: p.zone_ru, kk: p.zone_kk, en: p.zone_en };
  const payload = { ...p, actor: p.actor ?? "Dalada", zone: zones[language] ?? p.zone_ru ?? "" };
  const { title, body } = texts[language][row.kind](payload);
  let url: string | undefined;
  if (row.kind === "thread_reply" && p.thread_id) {
    url = `dalada://thread/${p.thread_id}`;
  } else if ((row.kind === "comment" || row.kind === "friend_post") && p.target_kind === "trip" && p.target_id) {
    url = `dalada://trip/${p.target_id}`;
  } else if (
    (row.kind === "friend_post" || row.kind === "ban_start" || row.kind === "ban_end" ||
      row.kind === "place_activity" || (row.kind === "moderation" && p.topic === "suggestion")) && p.place_id
  ) {
    url = `dalada://place/${p.place_id}`;
  } else if (row.kind === "comment" && p.target_kind && p.target_id) {
    url = `dalada://comments/${p.target_kind}/${p.target_id}`;
  } else if (p.username && row.kind !== "moderation") {
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
