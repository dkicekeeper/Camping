-- Проверочное уведомление (kind = test) для workflow Push check: уходит на все устройства человека.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(2);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');
insert into public.devices (token, user_id, environment, language)
values (repeat('ab', 32), '11111111-1111-1111-1111-111111111111', 'production', 'kk');

select ok(
  'test' = any (enum_range(null::public.push_kind)::text[]),
  'есть вид уведомления test'
);

insert into private.push_outbox (user_id, kind, payload)
values ('11111111-1111-1111-1111-111111111111', 'test', '{}');

set local role service_role;
select is(
  (select array_agg(kind::text || ':' || language) from public.push_claim(10)),
  array['test:kk'],
  'проверочное уведомление забирается на устройство человека'
);

select * from finish();
rollback;
