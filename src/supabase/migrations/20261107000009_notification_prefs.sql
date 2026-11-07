-- Tùy chọn loại thông báo theo tài khoản (Phase 1 bước 4.4–4.5): áp cho mọi thiết bị, và fan-out tôn trọng nó.
-- Key = mã `notification_types` (lookup). Thiếu key → mặc định bật (thêm loại mới không làm ai mất thông báo).
alter table public.profiles
  add column notification_prefs jsonb not null default '{}'::jsonb
    check (jsonb_typeof(notification_prefs) = 'object' and pg_column_size(notification_prefs) <= 1024);

create or replace function public.my_notification_prefs()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce((select p.notification_prefs from public.profiles p where p.id = auth.uid()), '{}'::jsonb);
$$;

-- Chỉ nhận key là mã notification_types hợp lệ, giá trị boolean.
create or replace function public.set_notification_prefs(prefs jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(prefs) <> 'object'
     or exists (select 1 from jsonb_each(prefs) e
                where jsonb_typeof(e.value) <> 'boolean'
                   or not exists (select 1 from public.lookup_items l
                                  where l.category = 'notification_types' and l.code = e.key)) then
    raise exception 'invalid notification prefs' using errcode = '22023';
  end if;
  update public.profiles set notification_prefs = prefs where id = auth.uid();
end;
$$;

-- Fan-out: như migration 04 + bỏ người đã tắt loại thông báo này.
create or replace function public.fan_out_project_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.projects;
  kind text;
  title text;
  body text;
  today_vn date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  select * into p from public.projects where id = new.project_id;

  if new.field in ('price_min', 'price_max') then
    kind := 'doi_gia';
    title := p.name || ' thay đổi giá';
    body := 'Giá tham khảo mới: ' || coalesce(p.price_min::text, '?') || '–' || coalesce(p.price_max::text, '?') || ' triệu/m².';
  elsif new.field = 'status' and new.new_value = to_jsonb('nhan_ho_so'::text) then
    kind := 'mo_nhan_ho_so';
    title := p.name || ' mở nhận hồ sơ';
    body := case when p.application_start is null then 'Dự án bắt đầu nhận hồ sơ.'
                 else 'Nhận hồ sơ từ ' || to_char(p.application_start, 'DD/MM') || ' đến ' || to_char(p.application_end, 'DD/MM') || '.' end;
  else
    kind := 'doi_trang_thai';
    title := p.name || ' cập nhật thông tin';
    body := 'Trạng thái hoặc khung nhận hồ sơ vừa thay đổi. Mở app để xem chi tiết.';
  end if;

  insert into public.notifications (user_id, project_id, type, title, body)
  select b.user_id, p.id, kind, title, body
  from public.bookmarks b
  join public.profiles pr on pr.id = b.user_id
  where b.project_id = p.id
    and b.notify_enabled
    and coalesce((pr.notification_prefs ->> kind)::boolean, true)
    and not exists (
      select 1 from public.notifications n
      where n.user_id = b.user_id and n.project_id = p.id
        and (n.created_at at time zone 'Asia/Ho_Chi_Minh')::date = today_vn
    );
  return new;
end;
$$;

revoke execute on function public.my_notification_prefs() from public, anon;
revoke execute on function public.set_notification_prefs(jsonb) from public, anon;
grant execute on function public.my_notification_prefs() to authenticated;
grant execute on function public.set_notification_prefs(jsonb) to authenticated;
