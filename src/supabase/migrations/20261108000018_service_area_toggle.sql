-- Cờ ẩn/hiện (tạm ngừng phục vụ) một tỉnh — admin bật/tắt qua DB, KHÔNG cần phát hành app (2026-11-08).
-- Cờ duy nhất là `lookup_items.attributes ->> 'in_mvp'` (không thêm cờ thứ hai để khỏi lệch nhau). Khi in_mvp = false:
--   app: mất chip, tìm kiếm hiện "Sắp có", không chọn/khôi phục vùng đó;
--   server: không lưu/đề xuất địa điểm mới (mvp_service_area_at → AC403), staging từ chối bản nháp dự án;
--   (mới) dự án của tỉnh đó KHÔNG hiện trên bản đồ / kết quả tìm kiếm.
-- Giữ nguyên: dữ liệu đã có (dự án, địa điểm đã lưu, bookmark) — bookmark vẫn mở được qua projects_by_ids,
-- địa điểm đã lưu vẫn sửa tên/ghi chú/xóa được (update_saved_place không kiểm lại vị trí).

-- ───── 1. Dự án của tỉnh tạm ngừng không hiện trên bản đồ / tìm kiếm ─────
create or replace function public.projects_in_bbox(
  min_lng double precision, min_lat double precision,
  max_lng double precision, max_lat double precision,
  statuses text[] default null,
  service_areas text[] default null
)
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select public.project_json(p)
  from public.projects p
  join public.lookup_items l
    on l.category = 'service_areas' and l.code = p.service_area and l.attributes ->> 'in_mvp' = 'true'
  where p.location operator(extensions.&&)
        extensions.st_makeenvelope(min_lng, min_lat, max_lng, max_lat, 4326)::extensions.geography
    and (statuses is null or cardinality(statuses) = 0 or p.status = any (statuses))
    and (service_areas is null or cardinality(service_areas) = 0 or p.service_area = any (service_areas))
  order by p.name
  limit 500;
$$;

create or replace function public.search_places(q text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with needle as (select public.normalize_search(q) as n),
  units as (
    select u.* from public.administrative_units u, needle
    where char_length(needle.n) >= 2
      and exists (
        select 1 from unnest(array_prepend(u.name, u.old_names)) as candidate
        where public.normalize_search(candidate) like '%' || needle.n || '%'
      )
  ),
  matched_projects as (
    select p.* from public.projects p, needle
    where char_length(needle.n) >= 2
      and exists (select 1 from public.lookup_items l
                  where l.category = 'service_areas' and l.code = p.service_area and l.attributes ->> 'in_mvp' = 'true')
      and (public.normalize_search(p.name) like '%' || needle.n || '%'
           or p.ward_code in (select code from units))
    order by p.name
    limit 20
  )
  select jsonb_build_object(
    'projects', (select coalesce(jsonb_agg(public.project_json(mp)), '[]'::jsonb) from matched_projects mp),
    -- Phường/xã vẫn trả về kể cả khi tỉnh tạm ngừng: app dựa vào service_area để báo "Sắp có" thay vì "không thấy".
    'places', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', u.code, 'name', u.name, 'province', u.province, 'service_area', u.service_area,
        'old_names', to_jsonb(u.old_names), 'center', public.point_json(u.center)
      ) order by u.name), '[]'::jsonb) from units u)
  );
$$;

-- ───── 2. Hàm admin bật/tắt (DBeaver) ─────
-- select ingest.set_service_area_active('lam_dong', false, 'chưa có dự án');   -- ẩn
-- select ingest.set_service_area_active('lam_dong', true);                     -- hiện lại
-- Trả về số dữ liệu đang có trong tỉnh để admin biết ảnh hưởng. App nhận thay đổi ở lần tải danh mục kế tiếp (mở lại app).
create or replace function ingest.set_service_area_active(code text, active boolean, reason text default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  item public.lookup_items;
begin
  select * into item from public.lookup_items l
  where l.category = 'service_areas' and l.code = set_service_area_active.code
  for update;
  if not found then
    raise exception 'không có vùng % trong danh mục service_areas', code using errcode = '22023';
  end if;
  if item.attributes ? 'merged_into' then
    raise exception 'vùng % là mã cũ đã gộp vào % — không bật/tắt được', code, item.attributes ->> 'merged_into'
      using errcode = '22023';
  end if;
  if active is null then
    raise exception 'active phải là true/false' using errcode = '22023';
  end if;
  if not active and nullif(btrim(reason), '') is null then
    raise exception 'tạm ngừng phải có lý do' using errcode = '22023';
  end if;
  -- Bật mà thiếu ranh giới/tâm → chip không highlight được, lưu địa điểm luôn AC403 → chặn.
  if active and (item.center is null
                 or not exists (select 1 from public.service_area_boundaries b where b.code = item.code)) then
    raise exception 'vùng % chưa có ranh giới hoặc tâm — nạp ranh giới trước khi bật', code using errcode = '22023';
  end if;
  if not active and not exists (select 1 from public.lookup_items l
                                where l.category = 'service_areas' and l.code <> item.code
                                  and l.attributes ->> 'in_mvp' = 'true') then
    raise exception 'không tắt được vùng phục vụ cuối cùng' using errcode = '22023';
  end if;

  update public.lookup_items l
  set attributes = case when active
        then (l.attributes - 'paused_reason' - 'paused_at') || '{"in_mvp": "true"}'::jsonb
        else l.attributes || jsonb_build_object('in_mvp', 'false', 'paused_reason', btrim(reason),
                                                'paused_at', to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD"T"HH24:MI'))
      end
  where l.category = 'service_areas' and l.code = item.code;

  return jsonb_build_object(
    'code', item.code,
    'in_mvp', active,
    'projects', (select count(*) from public.projects p where p.service_area = item.code),
    'saved_places', (select count(*) from public.saved_places s where s.service_area = item.code),
    'bookmarks', (select count(*) from public.bookmarks b join public.projects p on p.id = b.project_id
                  where p.service_area = item.code)
  );
end;
$$;

revoke execute on function ingest.set_service_area_active(text, boolean, text) from public, anon, authenticated;
