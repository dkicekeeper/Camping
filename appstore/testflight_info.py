#!/usr/bin/env python3
"""Тексты TestFlight в App Store Connect из файлов appstore/testflight/ — через App Store Connect API.

    python3 appstore/testflight_info.py [--build 110] [--wait 30] [--submit]

Выставляет:
  - Test Information: описание бета-версии, почта для отзывов, политика конфиденциальности
    (beta_description.<locale>.txt);
  - Beta App Review Information: заметки для проверяющих (review_notes.txt), вход без
    демо-аккаунта; почту для связи — если не задана. Имя и телефон контакта не трогает;
  - What to Test у сборки (what_to_test.<locale>.txt): указанной или последней.
В конце печатает состояние последних сборок (обработка, внутреннее и внешнее тестирование).

--wait N    — ждать до N минут, пока сборка появится и обработается (после загрузки).
--submit    — добавить сборку во внешние группы и отправить на бета-проверку Apple, если нужно.

Нужны ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH (файл .p8) — как в .github/workflows/testflight.yml.
Контактные данные в лог не выводятся: логи Actions открытого репозитория видны всем.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

TEXTS = Path(__file__).resolve().parent / "testflight"
BUNDLE_ID = "app.dalada.ios"
LOCALES = ["en-US", "ru"]
FEEDBACK_EMAIL = "dakacom@gmail.com"
PRIVACY_POLICY = "https://dkicekeeper.github.io/Dalada/privacy-policy.html"
API = "https://api.appstoreconnect.apple.com/v1"

_token = {"value": "", "exp": 0}


def token() -> str:
    now = int(time.time())
    if _token["exp"] - now < 60:
        _token["value"] = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
            Path(os.environ["ASC_KEY_PATH"]).read_text(),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
        )
        _token["exp"] = now + 1200
    return _token["value"]


class ApiError(Exception):
    def __init__(self, code: int, text: str):
        super().__init__(f"HTTP {code}: {text}")
        self.code = code


def call(method: str, path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        try:
            errors = json.loads(details).get("errors", [])
            details = "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors) or details
        except ValueError:
            pass
        raise ApiError(error.code, details[:600]) from None


def text(name: str) -> str:
    return (TEXTS / name).read_text(encoding="utf-8").strip()


def upsert(kind: str, existing: dict | None, attributes: dict, relationship: tuple[str, str, str]) -> None:
    """PATCH существующего объекта или POST нового со связью (имя, тип, id)."""
    if existing:
        call("PATCH", f"/{kind}/{existing['id']}",
             {"data": {"type": kind, "id": existing["id"], "attributes": attributes}})
    else:
        name, rel_type, rel_id = relationship
        call("POST", f"/{kind}", {"data": {"type": kind, "attributes": attributes,
                                           "relationships": {name: {"data": {"type": rel_type, "id": rel_id}}}}})


def update_app_information(app_id: str) -> None:
    current = {item["attributes"]["locale"]: item for item in call("GET", f"/apps/{app_id}/betaAppLocalizations")["data"]}
    for locale in LOCALES:
        attributes = {
            "description": text(f"beta_description.{locale}.txt"),
            "feedbackEmail": FEEDBACK_EMAIL,
            "privacyPolicyUrl": PRIVACY_POLICY,
        }
        upsert("betaAppLocalizations", current.get(locale), {**attributes, **({} if locale in current else {"locale": locale})},
               ("app", "apps", app_id))
        print(f"Test Information ({locale}): описание, почта для отзывов, политика — готово")

    detail = call("GET", f"/apps/{app_id}/betaAppReviewDetail")["data"]
    attributes = {"notes": text("review_notes.txt"), "demoAccountRequired": False}
    if not detail["attributes"].get("contactEmail"):
        attributes["contactEmail"] = FEEDBACK_EMAIL
    call("PATCH", f"/betaAppReviewDetails/{detail['id']}",
         {"data": {"type": "betaAppReviewDetails", "id": detail["id"], "attributes": attributes}})
    missing = [label for key, label in (("contactFirstName", "имя"), ("contactLastName", "фамилия"),
                                        ("contactPhone", "телефон")) if not detail["attributes"].get(key)]
    print("Beta App Review Information: заметки для проверяющих, вход без демо-аккаунта — готово")
    if missing:
        print(f"::warning::Контакт для бета-проверки: не заполнено — {', '.join(missing)}. "
              "App Store Connect → TestFlight → Test Information → Beta App Review Information.")


def builds(app_id: str, limit: int = 15) -> list[dict]:
    query = urllib.parse.urlencode({
        "filter[app]": app_id, "sort": "-uploadedDate", "limit": limit,
        "include": "preReleaseVersion,buildBetaDetail",
    })
    response = call("GET", "/builds?" + query)
    included = {(item["type"], item["id"]): item["attributes"] for item in response.get("included", [])}
    result = []
    for build in response["data"]:
        rel = build["relationships"]
        version = rel["preReleaseVersion"]["data"]
        beta = rel["buildBetaDetail"]["data"]
        result.append({
            "id": build["id"],
            "number": build["attributes"]["version"],
            "processing": build["attributes"]["processingState"],
            "expired": build["attributes"].get("expired", False),
            "version": included.get(("preReleaseVersions", version["id"]), {}).get("version", "?") if version else "?",
            "internal": included.get(("buildBetaDetails", beta["id"]), {}).get("internalBuildState", "?") if beta else "?",
            "external": included.get(("buildBetaDetails", beta["id"]), {}).get("externalBuildState", "?") if beta else "?",
        })
    return result


def find_build(app_id: str, number: str | None, wait_minutes: int) -> dict:
    deadline = time.time() + wait_minutes * 60
    while True:
        found = builds(app_id)
        build = next((b for b in found if b["number"] == number), None) if number else (found[0] if found else None)
        if build and build["processing"] != "PROCESSING":
            return build
        if time.time() > deadline:
            if build:
                return build
            sys.exit(f"::error::Сборка {number or '(последняя)'} не появилась в App Store Connect")
        print(f"Жду сборку {number or ''}: {build['processing'] if build else 'ещё не видна'}…")
        time.sleep(60)


def update_build(build: dict) -> None:
    current = {item["attributes"]["locale"]: item for item in call("GET", f"/builds/{build['id']}/betaBuildLocalizations")["data"]}
    for locale in LOCALES:
        attributes = {"whatsNew": text(f"what_to_test.{locale}.txt")}
        if locale not in current:
            attributes["locale"] = locale
        upsert("betaBuildLocalizations", current.get(locale), attributes, ("build", "builds", build["id"]))
    print(f"What to Test у сборки {build['number']} ({', '.join(LOCALES)}) — готово")


def submit(app_id: str, build: dict) -> None:
    if build["processing"] != "VALID":
        print(f"::warning::Сборка {build['number']} ещё не обработана ({build['processing']}) — не отправляю")
        return
    groups = [g for g in call("GET", f"/apps/{app_id}/betaGroups?limit=50")["data"] if not g["attributes"]["isInternalGroup"]]
    for group in groups:
        try:
            call("POST", f"/betaGroups/{group['id']}/relationships/builds",
                 {"data": [{"type": "builds", "id": build["id"]}]})
            print(f"Сборка {build['number']} добавлена во внешнюю группу «{group['attributes']['name']}»")
        except ApiError as error:
            print(f"::warning::Группа «{group['attributes']['name']}»: {error}")
    if not groups:
        print("::warning::Внешних групп нет — сборку некуда добавить")
    state = next(b for b in builds(app_id) if b["id"] == build["id"])["external"]
    if state in ("READY_FOR_BETA_SUBMISSION", "MISSING_EXPORT_COMPLIANCE"):
        try:
            call("POST", "/betaAppReviewSubmissions",
                 {"data": {"type": "betaAppReviewSubmissions",
                           "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
            print(f"Сборка {build['number']} отправлена на бета-проверку Apple")
        except ApiError as error:
            print(f"::warning::Отправить на бета-проверку не удалось: {error}")
    else:
        print(f"Сборка {build['number']}: внешнее тестирование — {state}, отправлять не нужно")


def report(app_id: str) -> None:
    lines = ["| Сборка | Версия | Обработка | Внутреннее | Внешнее |", "|---|---|---|---|---|"]
    for b in builds(app_id):
        processing = "EXPIRED" if b["expired"] else b["processing"]
        lines.append(f"| {b['number']} | {b['version']} | {processing} | {b['internal']} | {b['external']} |")
    print("\n".join(lines))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Сборки в TestFlight\n\n" + "\n".join(lines) + "\n")


def main(argv: list[str]) -> None:
    number = argv[argv.index("--build") + 1] if "--build" in argv else None
    wait = int(argv[argv.index("--wait") + 1]) if "--wait" in argv else 0
    number = number or None

    apps = call("GET", "/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID}))["data"]
    if not apps:
        sys.exit(f"::error::Приложение {BUNDLE_ID} не найдено в App Store Connect")
    app_id = apps[0]["id"]

    update_app_information(app_id)
    build = find_build(app_id, number, wait)
    update_build(build)
    if "--submit" in argv:
        submit(app_id, build)
    report(app_id)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except ApiError as error:
        sys.exit(f"::error::App Store Connect API: {error}")
