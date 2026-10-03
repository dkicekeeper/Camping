-- Новые виды уведомлений (M12): запрет начинается и закончился рядом с вашими местами, новый отзыв
-- или отчёт в вашем публичном месте, решение по вашей правке или жалобе. Отдельной миграцией:
-- новое значение перечисления можно использовать только после коммита.
alter type public.push_kind add value if not exists 'ban_start';
alter type public.push_kind add value if not exists 'ban_end';
alter type public.push_kind add value if not exists 'place_activity';
alter type public.push_kind add value if not exists 'moderation';
