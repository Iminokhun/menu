-- ============================================================
--  Cafe Andalus вЂ” РїРµСЂРµС…РѕРґ РЅР° РґРІР° С„РёР»РёР°Р»Р°
--
--  РњРѕРґРµР»СЊ: С„РёР»РёР°Р»С‹ РїРѕР»РЅРѕСЃС‚СЊСЋ РЅРµР·Р°РІРёСЃРёРјС‹. РЈ РєР°Р¶РґРѕРіРѕ СЃРІРѕРё РєР°С‚РµРіРѕСЂРёРё
--  Рё СЃРІРѕРё С‚РѕРІР°СЂС‹, РґР°Р¶Рµ РµСЃР»Рё Р±Р»СЋРґРѕ РЅР°Р·С‹РІР°РµС‚СЃСЏ РѕРґРёРЅР°РєРѕРІРѕ. РћР±С‰РµРіРѕ
--  РєР°С‚Р°Р»РѕРіР° РЅРµС‚ вЂ” СЌС‚Рѕ РґРІР° РѕС‚РґРµР»СЊРЅС‹С… РјРµРЅСЋ РІ РѕРґРЅРѕР№ Р±Р°Р·Рµ.
--
--  РЁР°РіРё 1-3 Р±РµР·РѕРїР°СЃРЅС‹: РЅРёС‡РµРіРѕ РЅРµ СѓРґР°Р»СЏСЋС‚, С‚РµРєСѓС‰РµРµ РїСЂРёР»РѕР¶РµРЅРёРµ
--  РїСЂРѕРґРѕР»Р¶Р°РµС‚ СЂР°Р±РѕС‚Р°С‚СЊ. РЁР°Рі 4 РІС‹РїРѕР»РЅСЏС‚СЊ РўРћР›Р¬РљРћ РїРѕСЃР»Рµ С‚РѕРіРѕ, РєР°Рє
--  РїСЂРёР»РѕР¶РµРЅРёРµ РїРµСЂРµРµС…Р°Р»Рѕ РЅР° РЅРѕРІСѓСЋ СЃС…РµРјСѓ.
-- ============================================================


-- ============================================================
--  РЁРђР“ 1. Р¤РёР»РёР°Р»С‹
-- ============================================================

-- Р—Р°РјРµРЅСЏРµС‚ С‚Р°Р±Р»РёС†Сѓ shop, РІ РєРѕС‚РѕСЂРѕР№ Р±С‹Р»Р° СЂРѕРІРЅРѕ РѕРґРЅР° СЃС‚СЂРѕРєР°.
-- slug РїРѕРїР°РґР°РµС‚ РІ СЃСЃС‹Р»РєСѓ QR-РєРѕРґР°: ?branch=center
create table if not exists public.branches (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null,
  name       text    not null default 'CAFE ANDALUS',
  slogan     text    not null default '',
  phone      text    not null default '',
  logo_url   text    not null default '',
  qr_url     text    not null default '',
  is_active  boolean not null default true,
  sort_order integer not null default 0
);

-- РўРµРєСѓС‰РµРµ Р·Р°РІРµРґРµРЅРёРµ СЃС‚Р°РЅРѕРІРёС‚СЃСЏ РїРµСЂРІС‹Рј С„РёР»РёР°Р»РѕРј:
-- РґР°РЅРЅС‹Рµ Р±РµСЂС‘Рј РёР· shop, С‡С‚РѕР±С‹ РЅРµ РїРѕС‚РµСЂСЏС‚СЊ Р»РѕРіРѕС‚РёРї Рё СЃСЃС‹Р»РєСѓ QR.
insert into public.branches (slug, name, slogan, phone, logo_url, qr_url, sort_order)
select 'center', name, slogan, phone, logo_url, qr_url, 0
from public.shop
where id = 1
on conflict (slug) do nothing;

-- Р’С‚РѕСЂРѕР№ С„РёР»РёР°Р» Р·РґРµСЃСЊ РќР• СЃРѕР·РґР°С‘С‚СЃСЏ РЅР°РјРµСЂРµРЅРЅРѕ: РµРіРѕ Р·Р°РІРѕРґСЏС‚ РёР· Р°РґРјРёРЅРєРё
-- (РІРєР»Р°РґРєР° В«Р¤РёР»РёР°Р»В» в†’ В«РќРѕРІС‹Р№ С„РёР»РёР°Р»В»), РіРґРµ РЅР°Р·РІР°РЅРёРµ РІРІРѕРґРёС‚СЃСЏ РѕР±С‹С‡РЅС‹Рј
-- С‚РµРєСЃС‚РѕРј, Р° Р°РґСЂРµСЃ РґР»СЏ СЃСЃС‹Р»РєРё РїРѕРґСЃС‚Р°РІР»СЏРµС‚СЃСЏ СЃР°Рј. РџСЂРѕРїРёСЃС‹РІР°С‚СЊ РЅР°Р·РІР°РЅРёСЏ
-- РІ РјРёРіСЂР°С†РёРё Р·РЅР°С‡РёР»Рѕ Р±С‹ РјРµРЅСЏС‚СЊ SQL РєР°Р¶РґС‹Р№ СЂР°Р·, РєРѕРіРґР° РѕС‚РєСЂС‹РІР°РµС‚СЃСЏ Р·Р°Р».
--
-- РќР°Р·РІР°РЅРёРµ РїРµСЂРІРѕРіРѕ С„РёР»РёР°Р»Р° РІР·СЏС‚Рѕ РёР· shop Рё, СЃРєРѕСЂРµРµ РІСЃРµРіРѕ, Р·РІСѓС‡РёС‚ РєР°Рє
-- В«CAFE ANDALUSВ». РџРµСЂРµРёРјРµРЅРѕРІР°С‚СЊ РµРіРѕ Рё Р·Р°РґР°С‚СЊ СЃРІРѕР№ Р°РґСЂРµСЃ СЃСЃС‹Р»РєРё РјРѕР¶РЅРѕ
-- С‚Р°Рј Р¶Рµ РІ Р°РґРјРёРЅРєРµ, РїРѕРєР° QR-РєРѕРґС‹ РµС‰С‘ РЅРµ РЅР°РїРµС‡Р°С‚Р°РЅС‹.

alter table public.branches enable row level security;

drop policy if exists "read branches" on public.branches;
create policy "read branches" on public.branches for select using (true);

-- Р’РќРРњРђРќРР•: РєР°Рє Рё РІ supabase_setup.sql, Р·Р°РїРёСЃСЊ СЂР°Р·СЂРµС€РµРЅР° Р°РЅРѕРЅРёРјРЅРѕРјСѓ
-- РєР»СЋС‡Сѓ, РїРѕС‚РѕРјСѓ С‡С‚Рѕ Р°РґРјРёРЅРєР° С…РѕРґРёС‚ РІ Р±Р°Р·Сѓ С‚РµРј Р¶Рµ РїСѓР±Р»РёС‡РЅС‹Рј РєР»СЋС‡РѕРј.
-- РЎ РґРІСѓРјСЏ С„РёР»РёР°Р»Р°РјРё СЌС‚Рѕ Р·РЅР°С‡РёС‚, С‡С‚Рѕ РїРµСЂСЃРѕРЅР°Р» РѕРґРЅРѕРіРѕ С„РёР»РёР°Р»Р° РјРѕР¶РµС‚
-- РїСЂР°РІРёС‚СЊ РјРµРЅСЋ РґСЂСѓРіРѕРіРѕ, Р° Р»СЋР±РѕР№ РїРѕСЃРµС‚РёС‚РµР»СЊ вЂ” РѕР±Р°. РџСЂР°РІРёР»СЊРЅРѕРµ СЂРµС€РµРЅРёРµ вЂ”
-- РІС…РѕРґ С‡РµСЂРµР· Supabase Auth Рё РїРѕР»РёС‚РёРєРё СЃ РїСЂРѕРІРµСЂРєРѕР№ С„РёР»РёР°Р»Р°.
drop policy if exists "anon write branches" on public.branches;
create policy "anon write branches" on public.branches for all using (true) with check (true);


-- ============================================================
--  РЁРђР“ 2. РџСЂРёРІСЏР·РєР° РјРµРЅСЋ Рє С„РёР»РёР°Р»Сѓ
-- ============================================================

alter table public.categories
  add column if not exists branch_id uuid references public.branches(id) on delete cascade;
alter table public.products
  add column if not exists branch_id uuid references public.branches(id) on delete cascade;

-- Р’СЃС‘ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РµРµ РјРµРЅСЋ РїСЂРёРЅР°РґР»РµР¶РёС‚ РїРµСЂРІРѕРјСѓ С„РёР»РёР°Р»Сѓ
update public.categories
   set branch_id = (select id from public.branches where slug = 'center')
 where branch_id is null;
update public.products
   set branch_id = (select id from public.branches where slug = 'center')
 where branch_id is null;

-- РўРµРїРµСЂСЊ Р·Р°РїРёСЃСЊ Р±РµР· С„РёР»РёР°Р»Р° РЅРµРґРѕРїСѓСЃС‚РёРјР°
alter table public.categories alter column branch_id set not null;
alter table public.products   alter column branch_id set not null;

-- РџСЂРёР»РѕР¶РµРЅРёРµ РІС‹Р±РёСЂР°РµС‚ РїРѕ С„РёР»РёР°Р»Сѓ Рё СЃРѕСЂС‚РёСЂСѓРµС‚ РїРѕ РїРѕСЂСЏРґРєСѓ
create index if not exists categories_branch_idx on public.categories (branch_id, sort_order);
create index if not exists products_branch_idx   on public.products   (branch_id, sort_order);

-- Р—Р°С‰РёС‚Р° РѕС‚ СЂР°СЃСЃРёРЅС…СЂРѕРЅР°: С‚РѕРІР°СЂ РЅРµ РјРѕР¶РµС‚ РІРёСЃРµС‚СЊ РІ РєР°С‚РµРіРѕСЂРёРё РґСЂСѓРіРѕРіРѕ
-- С„РёР»РёР°Р»Р°. РЎРѕСЃС‚Р°РІРЅРѕР№ РІРЅРµС€РЅРёР№ РєР»СЋС‡ РЅРµ РґР°СЃС‚ СЌС‚РѕРіРѕ СЃРґРµР»Р°С‚СЊ РґР°Р¶Рµ РІСЂСѓС‡РЅСѓСЋ
-- С‡РµСЂРµР· С‚Р°Р±Р»РёС†С‹ РІ Supabase.
alter table public.categories
  drop constraint if exists categories_id_branch_uq;
alter table public.categories
  add constraint categories_id_branch_uq unique (id, branch_id);

alter table public.products
  drop constraint if exists products_category_id_fkey;
alter table public.products
  drop constraint if exists products_category_branch_fk;
alter table public.products
  add constraint products_category_branch_fk
  foreign key (category_id, branch_id)
  references public.categories (id, branch_id) on delete cascade;

-- РџСЂРёРјРµС‡Р°РЅРёРµ РїСЂРѕ categories.parent_id: РѕРЅ РїРѕ-РїСЂРµР¶РЅРµРјСѓ СЃСЃС‹Р»Р°РµС‚СЃСЏ РїСЂРѕСЃС‚Рѕ
-- РЅР° categories(id), С‚Рѕ РµСЃС‚СЊ РЅР° СѓСЂРѕРІРЅРµ Р±Р°Р·С‹ РїРѕРґРєР°С‚РµРіРѕСЂРёСЋ С‚РµРѕСЂРµС‚РёС‡РµСЃРєРё
-- РјРѕР¶РЅРѕ РїРѕРґРІРµСЃРёС‚СЊ Рє РєР°С‚РµРіРѕСЂРёРё РґСЂСѓРіРѕРіРѕ С„РёР»РёР°Р»Р°. РђРґРјРёРЅРєР° С‚Р°РєРѕРіРѕ РІР°СЂРёР°РЅС‚Р°
-- РЅРµ РїСЂРµРґР»РѕР¶РёС‚ вЂ” РІ СЃРїРёСЃРєРµ СЂРѕРґРёС‚РµР»РµР№ Р±СѓРґСѓС‚ С‚РѕР»СЊРєРѕ РєР°С‚РµРіРѕСЂРёРё С‚РµРєСѓС‰РµРіРѕ
-- С„РёР»РёР°Р»Р°. Р–С‘СЃС‚РєРёР№ Р·Р°РїСЂРµС‚ Р·РґРµСЃСЊ РјРµС€Р°РµС‚: РїСЂРё СѓРґР°Р»РµРЅРёРё СЂРѕРґРёС‚РµР»СЏ СЃСЂР°Р±РѕС‚Р°Р»Рѕ
-- Р±С‹ "on delete set null" СЃСЂР°Р·Сѓ РЅР° РґРІРµ РєРѕР»РѕРЅРєРё, РѕР±РЅСѓР»РёРІ Рё branch_id.


-- ============================================================
--  РЁРђР“ 3 (РћРџР¦РРћРќРђР›Р¬РќРћ). Р—Р°РіРѕС‚РѕРІРєР° РјРµРЅСЋ РґР»СЏ РІС‚РѕСЂРѕРіРѕ С„РёР»РёР°Р»Р°
--
--  РљРѕРїРёСЂСѓРµС‚ РєР°С‚РµРіРѕСЂРёРё Рё С‚РѕРІР°СЂС‹ РїРµСЂРІРѕРіРѕ С„РёР»РёР°Р»Р° РІРѕ РІС‚РѕСЂРѕР№, СЃРѕС…СЂР°РЅСЏСЏ
--  РІР»РѕР¶РµРЅРЅРѕСЃС‚СЊ РєР°С‚РµРіРѕСЂРёР№. РРјРµРµС‚ СЃРјС‹СЃР», РµСЃР»Рё С‡Р°СЃС‚СЊ Р±Р»СЋРґ СЃРѕРІРїР°РґР°РµС‚:
--  СѓРґР°Р»РёС‚СЊ Р»РёС€РЅРµРµ Рё РїРѕРїСЂР°РІРёС‚СЊ С†РµРЅС‹ Р±С‹СЃС‚СЂРµРµ, С‡РµРј РЅР°Р±РёРІР°С‚СЊ Р·Р°РЅРѕРІРѕ.
--
--  РљР°СЂС‚РёРЅРєРё РїСЂРё СЌС‚РѕРј РќР• РґСѓР±Р»РёСЂСѓСЋС‚СЃСЏ вЂ” РѕР±Рµ Р·Р°РїРёСЃРё СЃСЃС‹Р»Р°СЋС‚СЃСЏ РЅР° С‚РѕС‚ Р¶Рµ
--  С„Р°Р№Р» РІ Storage. Р•СЃР»Рё РїРѕС‚РѕРј Р·Р°РјРµРЅРёС‚СЊ С„РѕС‚Рѕ РІ РѕРґРЅРѕРј С„РёР»РёР°Р»Рµ,
--  Р·Р°РіСЂСѓР·РёС‚СЃСЏ РЅРѕРІС‹Р№ С„Р°Р№Р» Рё РІС‚РѕСЂРѕР№ С„РёР»РёР°Р» РЅРµ Р·Р°С‚СЂРѕРЅРµС‚.
--
--  Р•СЃР»Рё РјРµРЅСЋ РЅР°РїРѕР»РЅСЏРµС‚СЃСЏ СЃ РЅСѓР»СЏ вЂ” РїСЂРѕСЃС‚Рѕ РЅРµ РІС‹РїРѕР»РЅСЏР№С‚Рµ СЌС‚РѕС‚ С€Р°Рі.
--
--  Р’РђР–РќРћ: РІС‹РїРѕР»РЅСЏС‚СЊ СѓР¶Рµ РџРћРЎР›Р• С‚РѕРіРѕ, РєР°Рє РІС‚РѕСЂРѕР№ С„РёР»РёР°Р» Р·Р°РІРµРґС‘РЅ РІ Р°РґРјРёРЅРєРµ.
--  РџРµСЂРµРґ Р·Р°РїСѓСЃРєРѕРј Р·Р°РјРµРЅРёС‚Рµ 'Р’РўРћР РћР™-Р¤РР›РРђР›' РЅР° РµРіРѕ РЅР°СЃС‚РѕСЏС‰РёР№ Р°РґСЂРµСЃ СЃСЃС‹Р»РєРё вЂ”
--  С‚РѕС‚, С‡С‚Рѕ РїРѕРєР°Р·Р°РЅ РІ Р°РґРјРёРЅРєРµ РІ РїРѕР»Рµ В«slug РґР»СЏ СЃСЃС‹Р»РєРёВ».
-- ============================================================

-- begin;
--
-- create temp table cat_map on commit drop as
-- select id as old_id, gen_random_uuid() as new_id
--   from public.categories
--  where branch_id = (select id from public.branches where slug = 'center');
--
-- insert into public.categories
--   (id, parent_id, name, name_en, name_tr, image_url, is_visible, sort_order, branch_id)
-- select m.new_id,
--        pm.new_id,
--        c.name, c.name_en, c.name_tr, c.image_url, c.is_visible, c.sort_order,
--        (select id from public.branches where slug = 'ВТОРОЙ-ФИЛИАЛ')
--   from public.categories c
--   join cat_map m  on m.old_id  = c.id
--   left join cat_map pm on pm.old_id = c.parent_id
--  where c.branch_id = (select id from public.branches where slug = 'center');
--
-- insert into public.products
--   (category_id, name, name_en, name_tr, description, desc_en, desc_tr,
--    price, image_url, is_visible, sort_order, portions, branch_id)
-- select m.new_id,
--        p.name, p.name_en, p.name_tr, p.description, p.desc_en, p.desc_tr,
--        p.price, p.image_url, p.is_visible, p.sort_order, p.portions,
--        (select id from public.branches where slug = 'ВТОРОЙ-ФИЛИАЛ')
--   from public.products p
--   join cat_map m on m.old_id = p.category_id
--  where p.branch_id = (select id from public.branches where slug = 'center');
--
-- commit;


-- ============================================================
--  РЁРђР“ 4. РЈР±РѕСЂРєР° вЂ” РўРћР›Р¬РљРћ РїРѕСЃР»Рµ РѕР±РЅРѕРІР»РµРЅРёСЏ РїСЂРёР»РѕР¶РµРЅРёСЏ
--
--  РџРѕРєР° С‚Р°Р±Р»РёС†Р° shop РЅР° РјРµСЃС‚Рµ, СЃС‚Р°СЂР°СЏ РІРµСЂСЃРёСЏ РїСЂРёР»РѕР¶РµРЅРёСЏ СЂР°Р±РѕС‚Р°РµС‚:
--  РѕРЅР° С‡РёС‚Р°РµС‚ РѕС‚С‚СѓРґР° РЅР°Р·РІР°РЅРёРµ, СЃР»РѕРіР°РЅ, Р»РѕРіРѕС‚РёРї Рё QR.
--  РЈРґР°Р»СЏС‚СЊ, РєРѕРіРґР° РЅРѕРІР°СЏ РІРµСЂСЃРёСЏ СЃРѕР±СЂР°РЅР° Рё РїСЂРѕРІРµСЂРµРЅР°.
-- ============================================================

-- drop table public.shop;
