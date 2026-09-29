#!/bin/sh
# Xcode Cloud: генерирует проект из project.yml и файл секретов из переменных окружения
# рабочего процесса (App Store Connect → Xcode Cloud → Workflow → Environment):
#   SUPABASE_HOST — хост проекта без https://
#   SUPABASE_KEY  — publishable (anon) key (отметьте как Secret)
set -eu

brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH/ios"

cat > Config/Secrets.xcconfig <<SECRETS
SUPABASE_HOST = ${SUPABASE_HOST:-}
SUPABASE_KEY = ${SUPABASE_KEY:-}
SECRETS

xcodegen generate
