#!/bin/sh
# Пересоздаёт ios/Dalada.xcodeproj, если между двумя коммитами изменился ios/project.yml
# или в ios/Dalada/ добавились, удалились или переименовались файлы.
# Файлы Swift-пакета ios/Packages/DaladaKit Xcode подхватывает сам — для них генерация не нужна.
set -u

root=$(git rev-parse --show-toplevel)
from=$1
to=$2

needs_generate=0
[ -d "$root/ios/Dalada.xcodeproj" ] || needs_generate=1
git diff --quiet "$from" "$to" -- ios/project.yml 2>/dev/null || needs_generate=1
[ -n "$(git diff --name-only --diff-filter=ADR "$from" "$to" -- ios/Dalada 2>/dev/null)" ] && needs_generate=1

[ "$needs_generate" = 1 ] || exit 0

# GitHub Desktop и Xcode запускают хуки без Homebrew в PATH — ищем xcodegen сами.
xcodegen_bin=""
for candidate in "$(command -v xcodegen 2>/dev/null)" /opt/homebrew/bin/xcodegen /usr/local/bin/xcodegen "$HOME/bin/xcodegen"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    xcodegen_bin=$candidate
    break
  fi
done

if [ -z "$xcodegen_bin" ]; then
  echo "Dalada: изменился ios/project.yml или файлы приложения — выполните: cd ios && xcodegen generate"
  exit 0
fi

echo "Dalada: обновляю ios/Dalada.xcodeproj (xcodegen)…"
cd "$root/ios" && "$xcodegen_bin" generate --quiet
