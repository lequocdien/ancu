-- Phường/xã cho app (LookupRepository.administrativeUnits). Qua RPC thay vì đọc bảng:
-- cột geography qua PostgREST ra WKB hex, còn contract của app là {lat, lng} (architecture.md 5.5).
create or replace function public.administrative_units_all()
returns setof jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'code', u.code, 'name', u.name, 'province', u.province, 'service_area', u.service_area,
    'old_names', to_jsonb(u.old_names), 'center', public.point_json(u.center)
  )
  from public.administrative_units u
  order by u.name;
$$;
