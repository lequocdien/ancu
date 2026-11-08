-- pgTAP cho migration 14: icon tự chọn của địa điểm đã lưu.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e1', 'e1@test.vn');

select is((select count(*)::int from public.lookup_items where category = 'place_icons'), 16, 'place_icons có 16 icon (từ migration)');
select is((select count(*)::int from public.lookup_items where category = 'place_icons' and sf_symbol is null), 0, 'mọi icon có sf_symbol');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

select is(public.create_saved_place('Không icon', 10.8, 106.7, 'khac') -> 'icon', 'null'::jsonb, 'không chọn icon → null (icon theo loại)');
select is(public.create_saved_place('Chỗ làm', 10.8, 106.7, 'khac', null, null, null, 'cho_lam') ->> 'icon', 'cho_lam', 'lưu kèm icon');
select throws_ok($$ select public.create_saved_place('X', 10.8, 106.7, 'khac', null, null, null, 'house.fill') $$, '22023', null,
                 'tên SF Symbol / mã lạ → 22023 (chỉ nhận mã danh mục)');

select is(public.update_saved_place((select (p ->> 'id')::uuid from public.my_saved_places() p where p ->> 'name' = 'Chỗ làm'),
                                    'Chỗ làm', 'khac', null, 'truong_hoc') ->> 'icon', 'truong_hoc', 'đổi icon');
select is(public.update_saved_place((select (p ->> 'id')::uuid from public.my_saved_places() p where p ->> 'name' = 'Chỗ làm'),
                                    'Chỗ làm', 'khac', null) -> 'icon', 'null'::jsonb, 'bỏ icon → về icon theo loại');
select throws_ok($$ select public.update_saved_place((select (p ->> 'id')::uuid from public.my_saved_places() p limit 1),
                                                    'X', 'khac', null, 'khong_co') $$, '22023', null, 'đổi sang mã lạ → 22023');

select * from finish();
rollback;
