-- ============================================================
--  Cafe Andalus — закрыть запись в базу от посторонних
--
--  До этого файла меню мог править любой: PIN лежал открытым текстом
--  в коде веб-версии, а политики RLS разрешали запись анонимному ключу,
--  который тоже раздаётся каждому посетителю. Здесь право на запись
--  переходит к авторизованным пользователям Supabase Auth.
--
--  ВНИМАНИЕ. Запускать ТОЛЬКО после того, как вход администратора
--  проверен в работающем приложении. Если выполнить раньше, меню станет
--  нередактируемым: старая админка по PIN писать уже не сможет, а новая
--  ещё не проверена. Чтение меню гостями этот файл не трогает.
--
--  Порядок:
--    1. Создать пользователя в панели Supabase:
--       Authentication → Users → Add user → Create new user.
--       Поставить галочку Auto Confirm User, иначе вход не сработает
--       до подтверждения почты.
--    2. Собрать приложение, войти в админку этой почтой и паролем,
--       убедиться, что сохранение товара проходит.
--    3. Выполнить этот файл.
--    4. Снова проверить сохранение — уже под новыми политиками.
-- ============================================================


-- ---------- Убираем запись для анонимных ----------
-- Политики заведены в supabase_setup.sql и supabase_branches_migration.sql.
-- shop к этому моменту может быть уже удалена шагом 4 миграции,
-- поэтому обращаемся к ней только если таблица ещё существует.

do $$
begin
  if to_regclass('public.shop') is not null then
    execute 'drop policy if exists "anon write shop" on public.shop';
  end if;
end $$;

drop policy if exists "anon write categories" on public.categories;
drop policy if exists "anon write products"   on public.products;
drop policy if exists "anon write branches"   on public.branches;


-- ---------- Запись только авторизованным ----------
-- `to authenticated` — ключевая часть: без неё политика действовала бы
-- и на анонимный ключ, и смысл изменения пропал бы.

drop policy if exists "auth write categories" on public.categories;
create policy "auth write categories" on public.categories
  for all to authenticated using (true) with check (true);

drop policy if exists "auth write products" on public.products;
create policy "auth write products" on public.products
  for all to authenticated using (true) with check (true);

drop policy if exists "auth write branches" on public.branches;
create policy "auth write branches" on public.branches
  for all to authenticated using (true) with check (true);


-- ---------- Хранилище картинок ----------
-- Загрузка и удаление файлов тоже были открыты всем: любой посетитель
-- мог залить что угодно в бакет заведения. Чтение оставляем публичным,
-- иначе картинки в меню перестанут показываться.

drop policy if exists "upload Andalus" on storage.objects;
create policy "upload Andalus" on storage.objects
  for insert to authenticated with check (bucket_id = 'Andalus');

drop policy if exists "update Andalus" on storage.objects;
create policy "update Andalus" on storage.objects
  for update to authenticated using (bucket_id = 'Andalus');

drop policy if exists "delete Andalus" on storage.objects;
create policy "delete Andalus" on storage.objects
  for delete to authenticated using (bucket_id = 'Andalus');


-- ============================================================
--  Проверка: что осталось открытым
--  Выполнить отдельно и посмотреть результат. В колонке roles у всех
--  политик на запись должно быть {authenticated}, а {public} или {anon}
--  допустимы только у политик на чтение (cmd = SELECT).
-- ============================================================

-- select tablename, policyname, cmd, roles
--   from pg_policies
--  where schemaname = 'public'
--  order by tablename, cmd;


-- ============================================================
--  Следующий шаг, если понадобится: свой админ на каждый филиал.
--
--  Сейчас любой вошедший правит оба меню. Чтобы разделить, нужна
--  таблица соответствия пользователь → филиал, например
--  branch_admins (user_id uuid, branch_id uuid), и политики вида
--
--    using (branch_id in (
--      select branch_id from public.branch_admins
--       where user_id = auth.uid()))
--
--  Пока филиалами управляет один владелец, в этом нет необходимости.
-- ============================================================
