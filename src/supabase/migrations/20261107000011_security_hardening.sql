-- Rà soát bảo mật Phase 1 bước 5.3 (docs/02-specs/security-review.md).

-- 1. "Báo thông tin sai": policy INSERT cũ cho phép ghi thẳng bảng qua PostgREST → vượt giới hạn 10 lần/24h của RPC.
--    Chỉ cho ghi qua RPC (SECURITY DEFINER, tự gắn reporter_id = auth.uid()).
drop policy "own reports insert" on public.data_reports;
revoke insert on public.data_reports from authenticated;

alter function public.report_data(uuid, text) security definer;

-- 2. Analytics: chặn một install gửi quá nhiều (lỗi vòng lặp ở app, hoặc kẻ phá dùng một install_id).
--    Vượt 2.000 sự kiện/24h → bỏ lặng lẽ (trả 0, app không retry). Kẻ phá đổi install_id liên tục vẫn lọt —
--    lớp chặn đó phải ở gateway (rate limit theo IP), ghi trong security-review.md.
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
  if (select count(*) from public.analytics_events a
      where a.install_id = track_events.install_id and a.received_at > now() - interval '24 hours') >= 2000 then
    return 0;
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

create index analytics_events_install_received_idx on public.analytics_events (install_id, received_at);
