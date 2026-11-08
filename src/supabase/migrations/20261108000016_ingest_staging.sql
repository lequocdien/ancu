-- Staging dữ liệu thu thập → admin duyệt → bảng chính (data-strategy.md 2b, architecture.md 5.6).
-- - Schema `ingest` KHÔNG mở qua API (không thêm vào Exposed schemas), thu hồi mọi quyền của anon/authenticated.
-- - Người duyệt: login DB (`postgres` qua DBeaver / psql). Hàm duyệt chỉ cấp EXECUTE cho postgres.
-- - Duyệt = upsert theo id trong 1 transaction; `verified_at` = ngày duyệt (giờ VN); đợt `silent` không bắn thông báo.
-- - Trường tùy chọn để trống trong bản nháp = GIỮ giá trị hiện có (crawler không đọc được ≠ nguồn đã gỡ).

-- ───── 1. Độ chính xác hình học (tuyến, ga) ─────
alter table public.infrastructure_routes
  add column geometry_accuracy text not null default 'minh_hoa'
    check (geometry_accuracy in ('chinh_xac', 'gan_dung', 'minh_hoa'));
alter table public.infra_nodes
  add column geometry_accuracy text not null default 'minh_hoa'
    check (geometry_accuracy in ('chinh_xac', 'gan_dung', 'minh_hoa'));

create or replace function public.node_json(n public.infra_nodes)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', n.id, 'route_id', n.route_id, 'name', n.name, 'type', n.type,
    'location', public.point_json(n.location), 'geometry_accuracy', n.geometry_accuracy
  );
$$;

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
    'geometry_accuracy', r.geometry_accuracy,
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

-- ───── 2. Fan-out tôn trọng đợt nhập lặng ─────
-- Như migration 09 + bỏ qua khi phiên đang áp dụng một đợt `silent` (project_updates vẫn được ghi).
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
  if current_setting('ancu.silent_ingest', true) = 'on' then
    return new;
  end if;

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

-- ───── 3. Schema staging ─────
create schema ingest;
revoke all on schema ingest from public, anon, authenticated;

create table ingest.batches (
  id               uuid primary key default gen_random_uuid(),
  -- Nguồn: `qgis_manual`, `so_xay_dung_hcm`…
  source           text not null check (source ~ '^[a-z0-9_]{2,40}$'),
  -- Mã lần chạy crawler (tên thư mục runs/…) để truy ngược file + bằng chứng.
  run_ref          text,
  contract_version int not null check (contract_version >= 1),
  -- Nhập lần đầu / sửa định dạng hàng loạt: không bắn thông báo khi duyệt.
  silent           boolean not null default false,
  note             text,
  submitted_by     text not null default session_user,
  submitted_at     timestamptz not null default now()
);

-- Cột chung của mọi bảng nháp.
create table ingest.route_candidates (
  candidate_id      bigint generated always as identity primary key,
  batch_id          uuid not null references ingest.batches (id) on delete cascade,
  id                uuid not null,
  name              text,
  type              text,
  status            text,
  expected_year     int,
  color_hex         text,
  geom              extensions.geography(multilinestring, 4326),
  geometry_accuracy text,
  source_url        text,
  raw               jsonb not null default '{}'::jsonb,
  evidence_url      text,
  crawled_at        timestamptz,
  review_status     text not null default 'pending' check (review_status in ('pending', 'applied', 'rejected', 'superseded')),
  validation_errors text[] not null default '{}',
  reviewed_by       text,
  reviewed_at       timestamptz,
  review_note       text,
  created_at        timestamptz not null default now()
);

create table ingest.node_candidates (
  candidate_id      bigint generated always as identity primary key,
  batch_id          uuid not null references ingest.batches (id) on delete cascade,
  id                uuid not null,
  route_id          uuid,
  name              text,
  type              text,
  location          extensions.geography(point, 4326),
  geometry_accuracy text,
  raw               jsonb not null default '{}'::jsonb,
  evidence_url      text,
  crawled_at        timestamptz,
  review_status     text not null default 'pending' check (review_status in ('pending', 'applied', 'rejected', 'superseded')),
  validation_errors text[] not null default '{}',
  reviewed_by       text,
  reviewed_at       timestamptz,
  review_note       text,
  created_at        timestamptz not null default now()
);

create table ingest.project_candidates (
  candidate_id       bigint generated always as identity primary key,
  batch_id           uuid not null references ingest.batches (id) on delete cascade,
  id                 uuid not null,
  name               text,
  address            text,
  ward_code          text,
  service_area       text,
  -- Được thiếu: thông báo của Sở chỉ có địa chỉ; admin đặt vị trí khi duyệt.
  location           extensions.geography(point, 4326),
  needs_location     boolean generated always as (location is null) stored,
  status             text,
  legal_status       text,
  application_start  date,
  application_end    date,
  price_min          numeric(6, 2),
  price_max          numeric(6, 2),
  price_is_estimated boolean,
  unit_count         int,
  developer          text,
  cover_image_url    text,
  source_url         text,
  raw                jsonb not null default '{}'::jsonb,
  evidence_url       text,
  crawled_at         timestamptz,
  review_status      text not null default 'pending' check (review_status in ('pending', 'applied', 'rejected', 'superseded')),
  validation_errors  text[] not null default '{}',
  reviewed_by        text,
  reviewed_at        timestamptz,
  review_note        text,
  created_at         timestamptz not null default now()
);

-- Mỗi id chỉ có MỘT bản nháp đang chờ (bản mới tự đẩy bản cũ sang `superseded`).
create unique index route_candidates_one_pending on ingest.route_candidates (id) where review_status = 'pending';
create unique index node_candidates_one_pending on ingest.node_candidates (id) where review_status = 'pending';
create unique index project_candidates_one_pending on ingest.project_candidates (id) where review_status = 'pending';
create index route_candidates_batch_idx on ingest.route_candidates (batch_id);
create index node_candidates_batch_idx on ingest.node_candidates (batch_id);
create index project_candidates_batch_idx on ingest.project_candidates (batch_id);

alter table ingest.batches enable row level security;
alter table ingest.route_candidates enable row level security;
alter table ingest.node_candidates enable row level security;
alter table ingest.project_candidates enable row level security;
revoke all on all tables in schema ingest from public, anon, authenticated;

-- ───── 4. Đẩy bản cũ + kiểm tra khi ghi ─────
create or replace function ingest.supersede_previous()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  execute format(
    'update ingest.%I set review_status = ''superseded'', reviewed_at = now(), review_note = ''có bản nháp mới hơn'' '
    'where id = $1 and review_status = ''pending''', tg_table_name
  ) using new.id;
  return new;
end;
$$;

create or replace function ingest._lookup_ok(category text, code text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.lookup_items l where l.category = _lookup_ok.category and l.code = _lookup_ok.code);
$$;

create or replace function ingest.validate_route()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  errors text[] := '{}';
begin
  if coalesce(trim(new.name), '') = '' then errors := array_append(errors, 'thiếu tên'); end if;
  if not ingest._lookup_ok('route_types', new.type) then errors := array_append(errors, ('loại tuyến lạ: ' || coalesce(new.type, 'null'))); end if;
  if not ingest._lookup_ok('route_statuses', new.status) then errors := array_append(errors, ('trạng thái lạ: ' || coalesce(new.status, 'null'))); end if;
  if new.expected_year is not null and new.expected_year not between 1990 and 2100 then errors := array_append(errors, 'năm ngoài 1990–2100'); end if;
  if coalesce(new.color_hex, '') !~ '^#[0-9A-Fa-f]{6}$' then errors := array_append(errors, 'màu không phải #RRGGBB'); end if;
  if new.geom is null then errors := array_append(errors, 'thiếu hình học'); end if;
  if coalesce(new.geometry_accuracy, '') not in ('chinh_xac', 'gan_dung', 'minh_hoa') then errors := array_append(errors, 'geometry_accuracy lạ'); end if;
  if coalesce(new.source_url, '') !~ '^https?://' then errors := array_append(errors, 'source_url không phải http(s)'); end if;
  new.validation_errors := errors;
  return new;
end;
$$;

create or replace function ingest.validate_node()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  errors text[] := '{}';
begin
  if coalesce(trim(new.name), '') = '' then errors := array_append(errors, 'thiếu tên'); end if;
  if not ingest._lookup_ok('node_types', new.type) then errors := array_append(errors, ('loại nút lạ: ' || coalesce(new.type, 'null'))); end if;
  if new.location is null then errors := array_append(errors, 'thiếu vị trí'); end if;
  if coalesce(new.geometry_accuracy, '') not in ('chinh_xac', 'gan_dung', 'minh_hoa') then errors := array_append(errors, 'geometry_accuracy lạ'); end if;
  -- Tuyến phải có ở bảng chính hoặc đang chờ duyệt cùng đợt (approve_batch duyệt tuyến trước).
  if new.route_id is not null
     and not exists (select 1 from public.infrastructure_routes r where r.id = new.route_id)
     and not exists (select 1 from ingest.route_candidates c
                     where c.id = new.route_id and c.batch_id = new.batch_id and c.review_status = 'pending') then
    errors := array_append(errors, 'route_id không tồn tại');
  end if;
  new.validation_errors := errors;
  return new;
end;
$$;

create or replace function ingest.validate_project()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  errors text[] := '{}';
begin
  if coalesce(trim(new.name), '') = '' then errors := array_append(errors, 'thiếu tên'); end if;
  if coalesce(trim(new.address), '') = '' then errors := array_append(errors, 'thiếu địa chỉ'); end if;
  if not ingest._lookup_ok('service_areas', new.service_area) then errors := array_append(errors, ('vùng lạ: ' || coalesce(new.service_area, 'null'))); end if;
  if not ingest._lookup_ok('project_statuses', new.status) then errors := array_append(errors, ('trạng thái lạ: ' || coalesce(new.status, 'null'))); end if;
  if not ingest._lookup_ok('legal_statuses', new.legal_status) then errors := array_append(errors, ('pháp lý lạ: ' || coalesce(new.legal_status, 'null'))); end if;
  if new.ward_code is not null and not exists (select 1 from public.administrative_units u where u.code = new.ward_code) then
    errors := array_append(errors, ('phường lạ: ' || new.ward_code));
  end if;
  if new.application_start is not null and new.application_end is not null and new.application_start > new.application_end then
    errors := array_append(errors, 'ngày bắt đầu sau ngày kết thúc');
  end if;
  if new.price_min is not null and new.price_min <= 0 or new.price_max is not null and new.price_max <= 0 then
    errors := array_append(errors, 'giá phải > 0');
  end if;
  if new.price_min is not null and new.price_max is not null and new.price_min > new.price_max then
    errors := array_append(errors, 'giá thấp nhất > cao nhất');
  end if;
  if new.unit_count is not null and new.unit_count <= 0 then errors := array_append(errors, 'số căn phải > 0'); end if;
  -- Dự án MỚI phải đủ cặp (dự án đã có: trống = giữ giá trị cũ, kiểm sau khi gộp lúc duyệt).
  if not exists (select 1 from public.projects p where p.id = new.id) then
    if (new.price_min is null) <> (new.price_max is null) then errors := array_append(errors, 'giá phải đủ thấp nhất và cao nhất'); end if;
    if (new.application_start is null) <> (new.application_end is null) then
      errors := array_append(errors, 'khung nhận hồ sơ phải đủ ngày bắt đầu và kết thúc');
    end if;
  end if;
  if coalesce(new.source_url, '') !~ '^https?://' then errors := array_append(errors, 'source_url không phải http(s)'); end if;
  if new.cover_image_url is not null and new.cover_image_url !~ '^https?://' then errors := array_append(errors, 'ảnh bìa không phải http(s)'); end if;
  -- Vị trí: được thiếu (needs_location); có thì phải nằm trong vùng MVP (± 3 km như saved_places).
  if new.location is not null and public.mvp_service_area_at(
       extensions.st_y(new.location::extensions.geometry), extensions.st_x(new.location::extensions.geometry)) is null then
    errors := array_append(errors, 'vị trí ngoài vùng MVP');
  end if;
  new.validation_errors := errors;
  return new;
end;
$$;

create trigger route_candidates_supersede before insert on ingest.route_candidates
  for each row execute function ingest.supersede_previous();
create trigger node_candidates_supersede before insert on ingest.node_candidates
  for each row execute function ingest.supersede_previous();
create trigger project_candidates_supersede before insert on ingest.project_candidates
  for each row execute function ingest.supersede_previous();

-- Kiểm tra lại cả khi sửa bản nháp (vd admin sửa tay một trường trong DBeaver).
create trigger route_candidates_validate before insert or update on ingest.route_candidates
  for each row when (new.review_status = 'pending') execute function ingest.validate_route();
create trigger node_candidates_validate before insert or update on ingest.node_candidates
  for each row when (new.review_status = 'pending') execute function ingest.validate_node();
create trigger project_candidates_validate before insert or update on ingest.project_candidates
  for each row when (new.review_status = 'pending') execute function ingest.validate_project();

-- ───── 5. Duyệt / từ chối ─────
-- Đặt cờ nhập lặng theo đợt của bản nháp — đặt lại MỖI lần (không lây sang đợt khác trong cùng transaction).
create or replace function ingest._enter_batch(batch uuid)
returns void
language sql
set search_path = ''
as $$
  select set_config('ancu.silent_ingest',
                    case when (select b.silent from ingest.batches b where b.id = batch) then 'on' else 'off' end, true);
$$;

create or replace function ingest._today_vn()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Ho_Chi_Minh')::date;
$$;

create or replace function ingest.approve_route(candidate bigint, note text default null)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c ingest.route_candidates;
begin
  select * into c from ingest.route_candidates where candidate_id = candidate for update;
  if not found then raise exception 'route candidate % not found', candidate using errcode = 'P0002'; end if;
  if c.review_status <> 'pending' then raise exception 'route candidate % is %', candidate, c.review_status using errcode = '22023'; end if;
  if cardinality(c.validation_errors) > 0 then
    raise exception 'route candidate % invalid: %', candidate, array_to_string(c.validation_errors, '; ') using errcode = '22023';
  end if;
  perform ingest._enter_batch(c.batch_id);
  insert into public.infrastructure_routes (id, name, type, status, expected_year, color_hex, geom, geometry_accuracy, source_url, verified_at)
  values (c.id, trim(c.name), c.type, c.status, c.expected_year, c.color_hex, c.geom, c.geometry_accuracy, c.source_url, ingest._today_vn())
  on conflict (id) do update set
    name = excluded.name, type = excluded.type, status = excluded.status,
    expected_year = coalesce(excluded.expected_year, public.infrastructure_routes.expected_year),
    color_hex = excluded.color_hex, geom = excluded.geom, geometry_accuracy = excluded.geometry_accuracy,
    source_url = excluded.source_url, verified_at = excluded.verified_at;
  update ingest.route_candidates
  set review_status = 'applied', reviewed_by = session_user, reviewed_at = now(), review_note = note
  where candidate_id = candidate;
  return c.id;
end;
$$;

create or replace function ingest.approve_node(candidate bigint, note text default null)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c ingest.node_candidates;
begin
  select * into c from ingest.node_candidates where candidate_id = candidate for update;
  if not found then raise exception 'node candidate % not found', candidate using errcode = 'P0002'; end if;
  if c.review_status <> 'pending' then raise exception 'node candidate % is %', candidate, c.review_status using errcode = '22023'; end if;
  if cardinality(c.validation_errors) > 0 then
    raise exception 'node candidate % invalid: %', candidate, array_to_string(c.validation_errors, '; ') using errcode = '22023';
  end if;
  if c.route_id is not null and not exists (select 1 from public.infrastructure_routes r where r.id = c.route_id) then
    raise exception 'node candidate %: duyệt tuyến % trước', candidate, c.route_id using errcode = '22023';
  end if;
  perform ingest._enter_batch(c.batch_id);
  insert into public.infra_nodes (id, route_id, name, type, location, geometry_accuracy)
  values (c.id, c.route_id, trim(c.name), c.type, c.location, c.geometry_accuracy)
  on conflict (id) do update set
    route_id = excluded.route_id, name = excluded.name, type = excluded.type,
    location = excluded.location, geometry_accuracy = excluded.geometry_accuracy;
  update ingest.node_candidates
  set review_status = 'applied', reviewed_by = session_user, reviewed_at = now(), review_note = note
  where candidate_id = candidate;
  return c.id;
end;
$$;

-- lat/lng: vị trí admin đặt khi bản nháp thiếu (hoặc muốn sửa). Trường tùy chọn trống = giữ giá trị hiện có.
create or replace function ingest.approve_project(
  candidate bigint,
  lat double precision default null,
  lng double precision default null,
  note text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c ingest.project_candidates;
begin
  select * into c from ingest.project_candidates where candidate_id = candidate for update;
  if not found then raise exception 'project candidate % not found', candidate using errcode = 'P0002'; end if;
  if c.review_status <> 'pending' then raise exception 'project candidate % is %', candidate, c.review_status using errcode = '22023'; end if;
  if (lat is null) <> (lng is null) then raise exception 'cần cả lat và lng' using errcode = '22023'; end if;
  if lat is not null then
    -- Cập nhật vào bản nháp → trigger kiểm tra lại (gồm vị trí trong vùng MVP).
    update ingest.project_candidates
    set location = extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography
    where candidate_id = candidate
    returning * into c;
  end if;
  if c.location is null then
    raise exception 'project candidate % thiếu vị trí — truyền lat, lng', candidate using errcode = '22023';
  end if;
  if cardinality(c.validation_errors) > 0 then
    raise exception 'project candidate % invalid: %', candidate, array_to_string(c.validation_errors, '; ') using errcode = '22023';
  end if;
  perform ingest._enter_batch(c.batch_id);
  if exists (select 1 from public.projects p where p.id = c.id) then
    -- UPDATE (không INSERT … ON CONFLICT): Postgres kiểm CHECK trên dòng định chèn TRƯỚC khi xét conflict,
    -- nên bản nháp chỉ có price_max sẽ vi phạm "giá đủ cặp" dù dòng sau khi gộp hợp lệ.
    update public.projects p set
      name = trim(c.name), address = trim(c.address),
      ward_code = coalesce(c.ward_code, p.ward_code),
      service_area = c.service_area, location = c.location,
      status = c.status, legal_status = c.legal_status,
      application_start = coalesce(c.application_start, p.application_start),
      application_end = coalesce(c.application_end, p.application_end),
      price_min = coalesce(c.price_min, p.price_min),
      price_max = coalesce(c.price_max, p.price_max),
      price_is_estimated = coalesce(c.price_is_estimated, p.price_is_estimated),
      unit_count = coalesce(c.unit_count, p.unit_count),
      developer = coalesce(c.developer, p.developer),
      cover_image_url = coalesce(c.cover_image_url, p.cover_image_url),
      source_url = c.source_url, verified_at = ingest._today_vn()
    where p.id = c.id;
  else
    insert into public.projects (
      id, name, address, ward_code, service_area, location, status, legal_status,
      application_start, application_end, price_min, price_max, price_is_estimated,
      unit_count, developer, cover_image_url, source_url, verified_at
    ) values (
      c.id, trim(c.name), trim(c.address), c.ward_code, c.service_area, c.location, c.status, c.legal_status,
      c.application_start, c.application_end, c.price_min, c.price_max, coalesce(c.price_is_estimated, true),
      c.unit_count, c.developer, c.cover_image_url, c.source_url, ingest._today_vn()
    );
  end if;
  update ingest.project_candidates
  set review_status = 'applied', reviewed_by = session_user, reviewed_at = now(), review_note = note
  where candidate_id = candidate;
  return c.id;
end;
$$;

-- Duyệt cả đợt: tuyến → ga → dự án, ALL-OR-NOTHING (một bản lỗi → không áp dụng gì; từ chối bản lỗi trước).
-- Dự án thiếu vị trí phải duyệt riêng bằng approve_project(…, lat, lng).
create or replace function ingest.approve_batch(batch uuid, note text default null)
returns table (entity text, applied int)
language plpgsql
set search_path = ''
as $$
declare
  r record;
  routes_n int := 0;
  nodes_n int := 0;
  projects_n int := 0;
begin
  if not exists (select 1 from ingest.batches b where b.id = batch) then
    raise exception 'batch % not found', batch using errcode = 'P0002';
  end if;
  for r in select candidate_id from ingest.route_candidates where batch_id = batch and review_status = 'pending' order by candidate_id loop
    perform ingest.approve_route(r.candidate_id, note);
    routes_n := routes_n + 1;
  end loop;
  for r in select candidate_id from ingest.node_candidates where batch_id = batch and review_status = 'pending' order by candidate_id loop
    perform ingest.approve_node(r.candidate_id, note);
    nodes_n := nodes_n + 1;
  end loop;
  for r in select candidate_id from ingest.project_candidates where batch_id = batch and review_status = 'pending' order by candidate_id loop
    perform ingest.approve_project(r.candidate_id, null, null, note);
    projects_n := projects_n + 1;
  end loop;
  return query values ('route', routes_n), ('node', nodes_n), ('project', projects_n);
end;
$$;

-- entity: 'route' | 'node' | 'project'.
create or replace function ingest.reject(entity text, candidate bigint, note text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  rows_changed int;
begin
  if entity not in ('route', 'node', 'project') then
    raise exception 'entity phải là route | node | project' using errcode = '22023';
  end if;
  if coalesce(trim(note), '') = '' then
    raise exception 'cần lý do từ chối' using errcode = '22023';
  end if;
  execute format(
    'update ingest.%I set review_status = ''rejected'', reviewed_by = session_user, reviewed_at = now(), review_note = $2 '
    'where candidate_id = $1 and review_status = ''pending''', entity || '_candidates'
  ) using candidate, note;
  get diagnostics rows_changed = row_count;
  if rows_changed = 0 then
    raise exception '% candidate % không ở trạng thái pending', entity, candidate using errcode = 'P0002';
  end if;
end;
$$;

-- ───── 6. Xem trước khi duyệt (DBeaver) ─────
-- Mới hay sửa, trường nào đổi, hình học dời tối đa bao nhiêu mét (UTM 48N, EPSG:32648 — vùng TP.HCM).
create view ingest.pending_review as
select 'route'::text as entity, c.candidate_id, c.id, c.name, b.source, b.silent, c.batch_id,
       case when r.id is null then 'new' else 'update' end as change,
       case when r.id is null then '{}'::text[] else array_remove(array[
         case when r.name is distinct from trim(c.name) then 'name' end,
         case when r.type is distinct from c.type then 'type' end,
         case when r.status is distinct from c.status then 'status' end,
         case when c.expected_year is not null and r.expected_year is distinct from c.expected_year then 'expected_year' end,
         case when r.geometry_accuracy is distinct from c.geometry_accuracy then 'geometry_accuracy' end,
         case when r.source_url is distinct from c.source_url then 'source_url' end,
         case when c.geom is not null and not extensions.st_equals(r.geom::extensions.geometry, c.geom::extensions.geometry) then 'geom' end
       ], null) end as changed_fields,
       case when r.id is not null and c.geom is not null then round(extensions.st_hausdorffdistance(
         extensions.st_transform(r.geom::extensions.geometry, 32648),
         extensions.st_transform(c.geom::extensions.geometry, 32648))::numeric) end as moved_m,
       c.validation_errors, false as needs_location, c.evidence_url, c.crawled_at, c.created_at
from ingest.route_candidates c
join ingest.batches b on b.id = c.batch_id
left join public.infrastructure_routes r on r.id = c.id
where c.review_status = 'pending'
union all
select 'node', c.candidate_id, c.id, c.name, b.source, b.silent, c.batch_id,
       case when n.id is null then 'new' else 'update' end,
       case when n.id is null then '{}'::text[] else array_remove(array[
         case when n.name is distinct from trim(c.name) then 'name' end,
         case when n.type is distinct from c.type then 'type' end,
         case when n.route_id is distinct from c.route_id then 'route_id' end,
         case when n.geometry_accuracy is distinct from c.geometry_accuracy then 'geometry_accuracy' end,
         case when c.location is not null and not extensions.st_equals(n.location::extensions.geometry, c.location::extensions.geometry) then 'location' end
       ], null) end,
       case when n.id is not null and c.location is not null then round(extensions.st_distance(n.location, c.location)::numeric) end,
       c.validation_errors, false, c.evidence_url, c.crawled_at, c.created_at
from ingest.node_candidates c
join ingest.batches b on b.id = c.batch_id
left join public.infra_nodes n on n.id = c.id
where c.review_status = 'pending'
union all
select 'project', c.candidate_id, c.id, c.name, b.source, b.silent, c.batch_id,
       case when p.id is null then 'new' else 'update' end,
       case when p.id is null then '{}'::text[] else array_remove(array[
         case when p.name is distinct from trim(c.name) then 'name' end,
         case when p.address is distinct from trim(c.address) then 'address' end,
         case when p.status is distinct from c.status then 'status' end,
         case when p.legal_status is distinct from c.legal_status then 'legal_status' end,
         case when c.application_start is not null and p.application_start is distinct from c.application_start then 'application_start' end,
         case when c.application_end is not null and p.application_end is distinct from c.application_end then 'application_end' end,
         case when c.price_min is not null and p.price_min is distinct from c.price_min then 'price_min' end,
         case when c.price_max is not null and p.price_max is distinct from c.price_max then 'price_max' end,
         case when c.unit_count is not null and p.unit_count is distinct from c.unit_count then 'unit_count' end,
         case when c.developer is not null and p.developer is distinct from c.developer then 'developer' end,
         case when c.location is not null and not extensions.st_equals(p.location::extensions.geometry, c.location::extensions.geometry) then 'location' end
       ], null) end,
       case when p.id is not null and c.location is not null then round(extensions.st_distance(p.location, c.location)::numeric) end,
       c.validation_errors, c.needs_location, c.evidence_url, c.crawled_at, c.created_at
from ingest.project_candidates c
join ingest.batches b on b.id = c.batch_id
left join public.projects p on p.id = c.id
where c.review_status = 'pending';

-- ───── Quyền ─────
revoke all on all tables in schema ingest from public, anon, authenticated;
revoke execute on all functions in schema ingest from public, anon, authenticated;
