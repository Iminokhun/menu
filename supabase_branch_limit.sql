-- ============================================================
--  Cafe Andalus — жёсткий предел на число филиалов
--
--  Проверка в админке оказалась недостаточной: страница, открытая до
--  обновления, продолжает работать по старому коду и спокойно создаёт
--  лишние филиалы. Так в базе появились «kjhjk» и «;pk».
--
--  Правило «залов ровно два» — инвариант данных, а не поведение экрана,
--  поэтому держим его здесь. Интерфейс остаётся как удобство: он гасит
--  кнопку заранее, чтобы человек не упирался в ошибку.
-- ============================================================

create or replace function public.enforce_branch_limit()
returns trigger
language plpgsql
as $$
declare
  n integer;
begin
  select count(*) into n from public.branches;
  if n >= 2 then
    raise exception 'Разрешено не более 2 филиалов (сейчас %)', n
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists branches_limit on public.branches;

create trigger branches_limit
  before insert on public.branches
  for each row execute function public.enforce_branch_limit();

-- Примечание про одновременность: две вставки в параллельных транзакциях
-- теоретически могут обе увидеть count = 1 и пройти. Для админки, куда
-- заходит один человек с планшета, это не сценарий. Если когда-нибудь
-- понадобится строгая гарантия — брать pg_advisory_xact_lock перед счётом.

-- Проверка после применения: должно вернуть ошибку, а не создать строку.
-- insert into public.branches (slug, name) values ('test-limit', 'Проверка');
