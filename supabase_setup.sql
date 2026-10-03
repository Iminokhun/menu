-- ============================================================
--  Cafe Andalus — схема базы для нового проекта Supabase
--  Вставить целиком в SQL Editor и выполнить один раз.
--  Имена колонок восстановлены из кода: lib/database.dart
--  и lib/screens/admin/*.dart — менять их нельзя.
-- ============================================================

-- ---------- Заведение: ровно одна строка с id = 1 ----------
-- Админка обновляет её через .eq('id', 1), приложение читает .single()
create table if not exists public.shop (
  id       integer primary key,
  name     text not null default 'CAFE ANDALUS',
  slogan   text not null default 'Добро пожаловать',
  phone    text not null default '',
  logo_url text not null default '',
  qr_url   text not null default ''
);

insert into public.shop (id) values (1) on conflict (id) do nothing;

-- ---------- Категории ----------
-- id читается кодом как строка, поэтому uuid, а не integer.
-- parent_id задаёт подкатегории (второй уровень меню).
create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references public.categories(id) on delete set null,
  name       text    not null default '',
  name_en    text    not null default '',
  name_tr    text    not null default '',
  image_url  text    not null default '',
  is_visible boolean not null default true,
  sort_order integer not null default 0
);

-- ---------- Товары ----------
-- price — double precision, чтобы PostgREST отдавал число, а не строку:
-- код делает (json['price'] ?? 0).toDouble(), на строке это упадёт.
-- portions — массив вида [{"name":"Большая","price":450}]
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete cascade,
  name        text    not null default '',
  name_en     text    not null default '',
  name_tr     text    not null default '',
  description text    not null default '',
  desc_en     text    not null default '',
  desc_tr     text    not null default '',
  price       double precision not null default 0,
  image_url   text    not null default '',
  is_visible  boolean not null default true,
  sort_order  integer not null default 0,
  portions    jsonb   not null default '[]'::jsonb
);

-- Приложение всегда фильтрует по is_visible и сортирует по sort_order
create index if not exists categories_sort_idx on public.categories (sort_order);
create index if not exists products_sort_idx   on public.products   (sort_order);
create index if not exists products_category_idx on public.products (category_id);

-- ============================================================
--  ДОСТУП (RLS)
-- ============================================================
alter table public.shop       enable row level security;
alter table public.categories enable row level security;
alter table public.products   enable row level security;

-- Чтение меню — всем. Это нормально и безопасно.
create policy "read shop"       on public.shop       for select using (true);
create policy "read categories" on public.categories for select using (true);
create policy "read products"   on public.products   for select using (true);

-- ------------------------------------------------------------
--  ВНИМАНИЕ. Политики ниже разрешают ЗАПИСЬ анонимному ключу.
--
--  Они нужны, потому что админка приложения ходит в базу тем же
--  публичным ключом, что и обычный посетитель. Без них кнопки
--  «Сохранить» и «Удалить» перестанут работать.
--
--  Обратная сторона: PIN-код лежит открытым текстом в коде,
--  который скачивает каждый посетитель сайта. То есть менять
--  меню сможет любой, кто откроет ссылку из QR.
--
--  Правильное решение — вход администратора через Supabase Auth
--  и политики вида `to authenticated`. До тех пор эти строки
--  оставляют базу открытой на запись.
-- ------------------------------------------------------------
create policy "anon write shop"       on public.shop       for all using (true) with check (true);
create policy "anon write categories" on public.categories for all using (true) with check (true);
create policy "anon write products"   on public.products   for all using (true) with check (true);

-- ============================================================
--  ХРАНИЛИЩЕ КАРТИНОК
--  Имя бакета "Andalus" зашито в lib/image_upload.dart — важен регистр.
-- ============================================================
insert into storage.buckets (id, name, public)
values ('Andalus', 'Andalus', true)
on conflict (id) do nothing;

create policy "read Andalus"   on storage.objects for select using (bucket_id = 'Andalus');
create policy "upload Andalus" on storage.objects for insert with check (bucket_id = 'Andalus');
create policy "update Andalus" on storage.objects for update using (bucket_id = 'Andalus');
create policy "delete Andalus" on storage.objects for delete using (bucket_id = 'Andalus');
