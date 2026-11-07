-- An Cư — 4/5: RPC (contract với app) + trigger nghiệp vụ.
--
-- Mọi RPC trả JSON đúng shape mock JSON của app (snake_case, location {lat, lng}, ngày "YYYY-MM-DD")
-- để Supabase*Repository dùng lại DTO/mapper của Data/Mock. Đổi shape = đổi contract → phải đổi DTO cùng lúc.
-- RPC đọc chạy SECURITY INVOKER (RLS vẫn áp dụng). Chỉ các hàm cần vượt RLS mới SECURITY DEFINER, và luôn
-- set search_path = '' + tham chiếu đủ schema.

-- ───────────────────────── Helper JSON ─────────────────────────

create or replace function public.point_json(p extensions.geography)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'lat', extensions.st_y(p::extensions.geometry),
    'lng', extensions.st_x(p::extensions.geometry)
  );
$$;

create or replace function public.project_json(p public.projects)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'address', p.address,
    'ward_code', p.ward_code,
    'service_area', p.service_area,
    'location', public.point_json(p.location),
    'status', p.status,
    'legal_status', p.legal_status,
    'application_start', p.application_start,
    'application_end', p.application_end,
    'price_min', p.price_min,
    'price_max', p.price_max,
    'price_is_estimated', p.price_is_estimated,
    'unit_count', p.unit_count,
    'developer', p.developer,
    'cover_image_url', p.cover_image_url,
    'source_url', p.source_url,
    'verified_at', p.verified_at
  );
$$;

create or replace function public.node_json(n public.infra_nodes)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', n.id, 'route_id', n.route_id, 'name', n.name, 'type', n.type,
    'location', public.point_json(n.location)
  );
$$;

-- ───────────────────────── RPC đọc ─────────────────────────

-- Dự án trong khung nhìn. Giới hạn 500 để payload không phình khi zoom out.
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
  where p.location operator(extensions.&&)
        extensions.st_makeenvelope(min_lng, min_lat, max_lng, max_lat, 4326)::extensions.geography
    and (statuses is null or cardinality(statuses) = 0 or p.status = any (statuses))
    and (service_areas is null or cardinality(service_areas) = 0 or p.service_area = any (service_areas))
  order by p.name
  limit 500;
$$;

create or replace function public.projects_by_ids(ids uuid[])
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select public.project_json(p) from public.projects p where p.id = any (ids);
$$;

-- Tuyến theo loại, giản lược theo mức zoom. tolerance_degrees: 0 = giữ nguyên; zoom out → tăng (vd 0.002).
create or replace function public.routes(
  types text[] default null,
  tolerance_degrees double precision default 0
)
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'name', r.name, 'type', r.type, 'status', r.status,
    'expected_year', r.expected_year, 'color_hex', r.color_hex,
    'source_url', r.source_url, 'verified_at', r.verified_at,
    'segments', (
      select coalesce(jsonb_agg(segment order by path), '[]'::jsonb)
      from (
        select d.path, (
          select jsonb_agg(jsonb_build_object('lat', extensions.st_y(pt.geom), 'lng', extensions.st_x(pt.geom)) order by pt.path)
          from extensions.st_dumppoints(d.geom) pt
        ) as segment
        from extensions.st_dump(
          case when tolerance_degrees > 0
               then extensions.st_simplifypreservetopology(r.geom::extensions.geometry, tolerance_degrees)
               else r.geom::extensions.geometry end
        ) d
      ) s
    )
  )
  from public.infrastructure_routes r
  where types is null or cardinality(types) = 0 or r.type = any (types)
  order by r.name;
$$;

create or replace function public.route_nodes(route uuid)
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select public.node_json(n) from public.infra_nodes n where n.route_id = route order by n.name;
$$;

-- Chi tiết + ga/nút giao gần nhất (đọc từ bảng tính sẵn). Không có → lỗi P0002 (PostgREST trả 404 → RepositoryError.notFound).
create or replace function public.project_detail(project_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  p public.projects;
begin
  select * into p from public.projects where id = project_detail.project_id;
  if not found then
    raise exception 'project % not found', project_id using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'project', public.project_json(p),
    'cover_image_url', p.cover_image_url,
    'nearest_infra', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'node', public.node_json(n),
        'route_name', r.name,
        'route_type', r.type,
        'route_status', r.status,
        'expected_year', r.expected_year,
        'distance_meters', round(ni.distance_meters)
      ) order by ni.distance_meters), '[]'::jsonb)
      from public.project_nearest_infra ni
      join public.infra_nodes n on n.id = ni.node_id
      left join public.infrastructure_routes r on r.id = n.route_id
      where ni.project_id = p.id
    )
  );
end;
$$;

-- Tìm theo tên dự án và phường/xã (tên mới + tên cũ), không dấu. Tối đa 20 kết quả.
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
      and (public.normalize_search(p.name) like '%' || needle.n || '%'
           or p.ward_code in (select code from units))
    order by p.name
    limit 20
  )
  select jsonb_build_object(
    'projects', (select coalesce(jsonb_agg(public.project_json(mp)), '[]'::jsonb) from matched_projects mp),
    'places', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', u.code, 'name', u.name, 'province', u.province, 'service_area', u.service_area,
        'old_names', to_jsonb(u.old_names), 'center', public.point_json(u.center)
      ) order by u.name), '[]'::jsonb) from units u)
  );
$$;

-- Toàn bộ danh mục, nhóm theo category — app gọi 1 lần lúc khởi động rồi cache.
create or replace function public.lookup_catalog()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(category, items), '{}'::jsonb)
  from (
    select category, jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'code', code, 'label_vi', label_vi, 'sort_order', sort_order,
      'color_hex', color_hex, 'sf_symbol', sf_symbol,
      'attributes', nullif(attributes, '{}'::jsonb),
      'center', case when center is null then null else public.point_json(center) end
    )) order by sort_order, code) as items
    from public.lookup_items
    group by category
  ) grouped;
$$;

-- Luật hiện hành: với mỗi rule_key, bản mới nhất đã có hiệu lực (theo ngày giờ Việt Nam).
create or replace function public.eligibility_rules_current()
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'rule_key', r.rule_key, 'value_type', r.value_type,
    'value_number', r.value_number, 'value_text', r.value_text, 'value_codes', to_jsonb(r.value_codes),
    'legal_reference', r.legal_reference, 'effective_from', r.effective_from, 'is_mock', r.is_mock
  ))
  from (
    select distinct on (rule_key) *
    from public.eligibility_rules
    where effective_from <= (now() at time zone 'Asia/Ho_Chi_Minh')::date
    order by rule_key, effective_from desc
  ) r
  order by r.rule_key;
$$;

-- ───────────────────────── RPC của người dùng ─────────────────────────

create or replace function public.current_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  -- SECURITY DEFINER để đọc số điện thoại ở auth.users; chỉ trả dòng của chính người gọi, đã che số.
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'is_phone_verified', p.phone_verified,
    'masked_phone', case when u.phone is null or u.phone = '' then null
                         else '••• ' || right(u.phone, 3) end
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = auth.uid();
$$;

-- Gộp bookmark khách lưu tạm trên máy vào tài khoản. Id không còn tồn tại bị bỏ qua. Trả số dòng thêm mới.
create or replace function public.merge_guest_bookmarks(project_ids uuid[])
returns int
language plpgsql
set search_path = ''
as $$
declare
  inserted int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  insert into public.bookmarks (user_id, project_id)
  select auth.uid(), p.id from public.projects p where p.id = any (project_ids)
  on conflict do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

create or replace function public.report_data(project_id uuid, note text)
returns uuid
language sql
set search_path = ''
as $$
  insert into public.data_reports (project_id, reporter_id, note)
  values (report_data.project_id, auth.uid(), trim(note))
  returning id;
$$;

create or replace function public.inbox()
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', n.id, 'type', n.type, 'project_id', n.project_id, 'title', n.title, 'body', n.body,
    'created_at', n.created_at, 'is_read', n.read_at is not null
  )
  from public.notifications n
  where n.user_id = auth.uid()
  order by n.created_at desc
  limit 100;
$$;

create or replace function public.mark_notification_read(notification_id uuid)
returns void
language sql
set search_path = ''
as $$
  update public.notifications set read_at = now()
  where id = notification_id and user_id = auth.uid() and read_at is null;
$$;

-- Xóa tài khoản (App Store bắt buộc). Cascade xóa profile, bookmark, thông báo, push token, báo cáo.
-- TODO: khi có ảnh bình luận (Phase 2), xóa object Storage của người dùng trước.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- ───────────────────────── Trigger ─────────────────────────

-- Tạo profile khi đăng ký.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, phone_verified)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    new.phone_confirmed_at is not null
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Ghi lịch sử các trường người dùng quan tâm + cập nhật updated_at.
create or replace function public.log_project_updates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  watched text[] := array['status', 'legal_status', 'application_start', 'application_end', 'price_min', 'price_max'];
  field text;
  old_value jsonb;
  new_value jsonb;
begin
  new.updated_at := now();
  foreach field in array watched loop
    old_value := to_jsonb(old) -> field;
    new_value := to_jsonb(new) -> field;
    if old_value is distinct from new_value then
      insert into public.project_updates (project_id, field, old_value, new_value, changed_by)
      values (new.id, field, old_value, new_value, auth.uid());
    end if;
  end loop;
  return new;
end;
$$;

create trigger projects_log_updates
  before update on public.projects
  for each row execute function public.log_project_updates();

-- Fan-out thông báo tới người đã bật thông báo. Tối đa 1 thông báo/ngày/dự án/người (theo ngày giờ VN).
-- TODO(backend): Database Webhook trên notifications → Edge Function gửi APNs.
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
  where b.project_id = p.id
    and b.notify_enabled
    and not exists (
      select 1 from public.notifications n
      where n.user_id = b.user_id and n.project_id = p.id
        and (n.created_at at time zone 'Asia/Ho_Chi_Minh')::date = today_vn
    );
  return new;
end;
$$;

create trigger project_updates_fan_out
  after insert on public.project_updates
  for each row execute function public.fan_out_project_update();

-- Ga Metro gần nhất + nút giao gần nhất + điểm hạ tầng lớn trong 25 km (đường chim bay).
-- project_ids NULL = tính lại toàn bộ.
create or replace function public.refresh_project_nearest_infra(project_ids uuid[] default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.project_nearest_infra where project_ids is null or project_id = any (project_ids);

  insert into public.project_nearest_infra (project_id, node_id, distance_meters)
  select p.id, near.id, extensions.st_distance(p.location, near.location)
  from public.projects p
  cross join lateral (
    (select n.id, n.location from public.infra_nodes n where n.type = 'ga_metro'
       order by n.location operator(extensions.<->) p.location limit 1)
    union all
    (select n.id, n.location from public.infra_nodes n where n.type = 'nut_giao'
       order by n.location operator(extensions.<->) p.location limit 1)
    union all
    (select n.id, n.location from public.infra_nodes n where n.type = 'diem_hat_nhan'
       and extensions.st_dwithin(n.location, p.location, 25000))
  ) near
  where project_ids is null or p.id = any (project_ids);
end;
$$;

create or replace function public.refresh_nearest_for_project()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_project_nearest_infra(array[new.id]);
  return null;
end;
$$;

create trigger projects_refresh_nearest
  after insert or update of location on public.projects
  for each row execute function public.refresh_nearest_for_project();

create or replace function public.refresh_nearest_all()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_project_nearest_infra(null);
  return null;
end;
$$;

-- Đổi ga/nút giao → tính lại toàn bộ (ít dự án, ít thay đổi). Khi > vài nghìn dự án: chuyển sang job định kỳ.
create trigger infra_nodes_refresh_nearest
  after insert or update or delete on public.infra_nodes
  for each statement execute function public.refresh_nearest_all();

-- ───────────────────────── Quyền gọi RPC ─────────────────────────

-- Hàm nội bộ / trigger: không cho gọi qua API.
revoke execute on function public.refresh_project_nearest_infra(uuid[]) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.log_project_updates() from public, anon, authenticated;
revoke execute on function public.fan_out_project_update() from public, anon, authenticated;
revoke execute on function public.refresh_nearest_for_project() from public, anon, authenticated;
revoke execute on function public.refresh_nearest_all() from public, anon, authenticated;

-- RPC cần đăng nhập.
revoke execute on function public.current_profile() from public, anon;
revoke execute on function public.merge_guest_bookmarks(uuid[]) from public, anon;
revoke execute on function public.report_data(uuid, text) from public, anon;
revoke execute on function public.inbox() from public, anon;
revoke execute on function public.mark_notification_read(uuid) from public, anon;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.current_profile() to authenticated;
grant execute on function public.merge_guest_bookmarks(uuid[]) to authenticated;
grant execute on function public.report_data(uuid, text) to authenticated;
grant execute on function public.inbox() to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
