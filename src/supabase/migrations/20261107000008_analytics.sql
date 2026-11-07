-- Analytics tự làm (Phase 1 bước 5.1, architecture.md 5.6). Nguyên tắc riêng tư:
-- - Định danh = install_id ngẫu nhiên do app tạo; KHÔNG lưu user_id/email/IP/vị trí → "không liên kết danh tính" (App Privacy).
-- - Bảng không có policy SELECT → không client nào đọc được qua API; chỉ ghi qua RPC `track_events` (kiểm tra đầu vào).
-- - Đọc số liệu bằng SQL (service role / Studio): view retention + phễu bên dưới.

create table public.analytics_events (
  id           bigint generated always as identity primary key,
  install_id   uuid not null,
  name         text not null check (name ~ '^[a-z][a-z0-9_]{1,39}$'),
  props        jsonb not null default '{}'::jsonb check (pg_column_size(props) <= 2048),
  app_version  text not null check (char_length(app_version) <= 20),
  os_version   text not null check (char_length(os_version) <= 20),
  occurred_at  timestamptz not null,
  received_at  timestamptz not null default now()
);

create index analytics_events_install_idx on public.analytics_events (install_id, occurred_at);
create index analytics_events_name_idx on public.analytics_events (name, occurred_at);

alter table public.analytics_events enable row level security;
-- Không policy nào: anon/authenticated không đọc/ghi trực tiếp được.
-- Thu hồi luôn quyền bảng (mặc định Supabase grant cho anon/authenticated): lỡ thêm policy sai cũng không lộ.
revoke all on public.analytics_events from anon, authenticated;

-- Nhận một lô sự kiện. Lô lỗi định dạng → bỏ cả lô (22023), app không retry lô đó.
-- occurred_at bị kẹp trong [now - 7 ngày, now + 5 phút] để đồng hồ máy sai không làm hỏng retention.
create or replace function public.track_events(install_id uuid, app_version text, os_version text, events jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted int;
begin
  if jsonb_typeof(events) <> 'array' or jsonb_array_length(events) = 0 or jsonb_array_length(events) > 50 then
    raise exception 'events must be an array of 1..50 items' using errcode = '22023';
  end if;
  insert into public.analytics_events (install_id, name, props, app_version, os_version, occurred_at)
  select track_events.install_id,
         e ->> 'name',
         coalesce(e -> 'props', '{}'::jsonb),
         left(track_events.app_version, 20),
         left(track_events.os_version, 20),
         least(greatest(coalesce((e ->> 'occurred_at')::timestamptz, now()), now() - interval '7 days'), now() + interval '5 minutes')
  from jsonb_array_elements(events) e;
  get diagnostics inserted = row_count;
  return inserted;
exception
  when check_violation or invalid_datetime_format or datetime_field_overflow or not_null_violation then
    raise exception 'invalid event' using errcode = '22023';
end;
$$;

revoke execute on function public.track_events(uuid, text, text, jsonb) from public;
grant execute on function public.track_events(uuid, text, text, jsonb) to anon, authenticated;

-- ───── Số liệu (chỉ service role / Studio) ─────

-- Retention theo tuần: cohort = tuần đầu tiên thấy install, week_n = install có hoạt động ở tuần thứ n.
-- Ngưỡng mở Android (roadmap): retention W4 ≥ 20%.
create view public.analytics_weekly_retention
with (security_invoker = true) as
with activity as (
  select install_id, date_trunc('week', occurred_at at time zone 'Asia/Ho_Chi_Minh')::date as week
  from public.analytics_events
  group by 1, 2
),
cohorts as (
  select install_id, min(week) as cohort_week from activity group by 1
)
select c.cohort_week,
       count(distinct c.install_id) as installs,
       round(100.0 * count(distinct a.install_id) filter (where a.week = c.cohort_week + 7) / count(distinct c.install_id), 1) as w1_pct,
       round(100.0 * count(distinct a.install_id) filter (where a.week = c.cohort_week + 14) / count(distinct c.install_id), 1) as w2_pct,
       round(100.0 * count(distinct a.install_id) filter (where a.week = c.cohort_week + 28) / count(distinct c.install_id), 1) as w4_pct
from cohorts c
join activity a using (install_id)
group by c.cohort_week
order by c.cohort_week;

-- Phễu chính 28 ngày gần nhất: mở app → xem dự án → lưu → bật thông báo; và mở app → hoàn thành kiểm tra điều kiện.
create view public.analytics_funnel_28d
with (security_invoker = true) as
with recent as (
  select install_id, name from public.analytics_events where occurred_at > now() - interval '28 days'
)
select step, installs from (
  select 1 as ord, 'app_open' as step, count(distinct install_id) as installs from recent where name = 'app_open'
  union all select 2, 'project_viewed', count(distinct install_id) from recent where name = 'project_viewed'
  union all select 3, 'project_saved', count(distinct install_id) from recent where name = 'project_saved'
  union all select 4, 'notify_enabled', count(distinct install_id) from recent where name = 'notify_enabled'
  union all select 5, 'eligibility_completed', count(distinct install_id) from recent where name = 'eligibility_completed'
) f
order by ord;

revoke all on public.analytics_weekly_retention from anon, authenticated;
revoke all on public.analytics_funnel_28d from anon, authenticated;
