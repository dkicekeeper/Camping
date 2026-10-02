-- Новые значения перечислений для комментариев к постам и уведомлений о постах друзей (M10c).
-- Отдельной миграцией: новое значение перечисления можно использовать только после коммита.
alter type public.report_target add value if not exists 'comment';
alter type public.push_kind add value if not exists 'comment';
alter type public.push_kind add value if not exists 'friend_post';
