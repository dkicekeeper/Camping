-- Тестовое уведомление («Уведомления работают») — его кладёт в очередь workflow Push check
-- (.github/workflows/push-check.yml), чтобы проверить ключ APNs и секреты без второго аккаунта.
alter type public.push_kind add value if not exists 'test';
