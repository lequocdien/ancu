-- An Cư — 2/5: bảng nghiệp vụ.
-- Mẫu FK danh mục: cột `<x>_category` generated hằng số + FK (category, code) → lookup_items.
-- Chưa gồm comments / reports / user_blocks (Phase 2, sau Cổng C — roadmap.md).

-- Hồ sơ gắn với auth.users. Tạo tự động bởi trigger ở migration 4.
create table public.profiles (
  id                     uuid primary key references auth.users (id) on delete cascade,
  display_name           text not null default '' check (char_length(display_name) <= 80),
  phone_verified         boolean not null default false,
  approved_comment_count int not null default 0 check (approved_comment_count >= 0),
  role                   text not null default 'user' check (role in ('user', 'moderator', 'admin')),
  created_at             timestamptz not null default now()
);

create table public.projects (
  id                     uuid primary key default gen_random_uuid(),
  name                   text not null,
  address                text not null,
  ward_code              text references public.administrative_units (code),
  service_area           text not null,
  service_area_category  text generated always as ('service_areas') stored,
  location               extensions.geography(point, 4326) not null,
  status                 text not null,
  status_category        text generated always as ('project_statuses') stored,
  legal_status           text not null,
  legal_status_category  text generated always as ('legal_statuses') stored,
  application_start      date,
  application_end        date,
  price_min              numeric(6, 2) check (price_min > 0),
  price_max              numeric(6, 2) check (price_max > 0),
  price_is_estimated     boolean not null default true,
  unit_count             int check (unit_count > 0),
  developer              text,
  cover_image_url        text,
  source_url             text not null check (source_url ~ '^https?://'),
  verified_at            date not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  foreign key (service_area_category, service_area) references public.lookup_items (category, code),
  foreign key (status_category, status) references public.lookup_items (category, code),
  foreign key (legal_status_category, legal_status) references public.lookup_items (category, code),
  check ((application_start is null) = (application_end is null)),
  check (application_end >= application_start),
  check ((price_min is null) = (price_max is null)),
  check (price_max >= price_min)
);

create index projects_location_idx on public.projects using gist (location);
create index projects_status_idx on public.projects (status);

create table public.infrastructure_routes (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  type             text not null,
  type_category    text generated always as ('route_types') stored,
  status           text not null,
  status_category  text generated always as ('route_statuses') stored,
  expected_year    int check (expected_year between 1990 and 2100),
  color_hex        text not null check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  -- MultiLineString: tuyến khai thác từng đoạn (vd Vành đai 3) gồm nhiều đoạn rời.
  geom             extensions.geography(multilinestring, 4326) not null,
  source_url       text not null check (source_url ~ '^https?://'),
  verified_at      date not null,
  foreign key (type_category, type) references public.lookup_items (category, code),
  foreign key (status_category, status) references public.lookup_items (category, code)
);

create index infrastructure_routes_geom_idx on public.infrastructure_routes using gist (geom);

create table public.infra_nodes (
  id             uuid primary key default gen_random_uuid(),
  -- NULL: điểm không thuộc tuyến nào (vd Sân bay Long Thành).
  route_id       uuid references public.infrastructure_routes (id) on delete set null,
  name           text not null,
  type           text not null,
  type_category  text generated always as ('node_types') stored,
  location       extensions.geography(point, 4326) not null,
  foreign key (type_category, type) references public.lookup_items (category, code)
);

create index infra_nodes_location_idx on public.infra_nodes using gist (location);
create index infra_nodes_type_idx on public.infra_nodes (type);

-- Ga/nút giao gần nhất tính sẵn (PostGIS KNN). Làm mới bằng trigger ở migration 4.
create table public.project_nearest_infra (
  project_id      uuid not null references public.projects (id) on delete cascade,
  node_id         uuid not null references public.infra_nodes (id) on delete cascade,
  distance_meters double precision not null check (distance_meters >= 0),
  primary key (project_id, node_id)
);

-- Bookmark của tài khoản. Bookmark của khách nằm trên máy, gộp vào bằng merge_guest_bookmarks().
create table public.bookmarks (
  user_id        uuid not null references auth.users (id) on delete cascade,
  project_id     uuid not null references public.projects (id) on delete cascade,
  notify_enabled boolean not null default false,
  created_at     timestamptz not null default now(),
  primary key (user_id, project_id)
);

create index bookmarks_notify_idx on public.bookmarks (project_id) where notify_enabled;

-- Lịch sử thay đổi dự án: nguồn thông báo + bằng chứng khi tranh cãi thông tin.
create table public.project_updates (
  id          bigint generated always as identity primary key,
  project_id  uuid not null references public.projects (id) on delete cascade,
  field       text not null,
  old_value   jsonb,
  new_value   jsonb,
  changed_at  timestamptz not null default now(),
  changed_by  uuid
);

create index project_updates_project_idx on public.project_updates (project_id, changed_at desc);

-- Hộp thông báo trong app (tab Theo dõi). Push qua APNs đọc từ đây (Edge Function, sau).
create table public.notifications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  project_id     uuid not null references public.projects (id) on delete cascade,
  type           text not null,
  type_category  text generated always as ('notification_types') stored,
  title          text not null,
  body           text not null,
  created_at     timestamptz not null default now(),
  read_at        timestamptz,
  foreign key (type_category, type) references public.lookup_items (category, code)
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

create table public.push_tokens (
  user_id    uuid not null references auth.users (id) on delete cascade,
  token      text not null,
  platform   text not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- Nút "Báo thông tin sai". Xử lý trong 72 giờ (data-strategy.md).
create table public.data_reports (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  reporter_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  note        text not null check (char_length(trim(note)) between 1 and 500),
  status      text not null default 'moi' check (status in ('moi', 'dang_xu_ly', 'da_xu_ly', 'tu_choi')),
  created_at  timestamptz not null default now()
);

create index data_reports_open_idx on public.data_reports (created_at) where status in ('moi', 'dang_xu_ly');

-- Luật kiểm tra điều kiện. Nhiều phiên bản theo effective_from; "hiện hành" = bản mới nhất đã hiệu lực.
create table public.eligibility_rules (
  rule_key        text not null,
  value_type      text not null check (value_type in ('number', 'text', 'codes')),
  value_number    numeric,
  value_text      text,
  value_codes     text[],
  legal_reference text not null default '',
  effective_from  date not null,
  is_mock         boolean not null default false,
  primary key (rule_key, effective_from),
  check (
    (value_type = 'number' and value_number is not null and value_text is null and value_codes is null) or
    (value_type = 'text'   and value_text   is not null and value_number is null and value_codes is null) or
    (value_type = 'codes'  and value_codes  is not null and value_number is null and value_text is null)
  )
);

-- Cấu hình từ xa: min_supported_version (force update), ngưỡng kiểm duyệt…
create table public.app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
