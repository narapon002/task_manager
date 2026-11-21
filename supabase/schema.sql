-- =====================================================================
-- ติดตามโปรเจค (Task Manager) — โครงสร้างฐานข้อมูล Supabase
-- รันครั้งเดียวใน SQL Editor ของโปรเจคใหม่ (หรือผ่าน migration)
-- ผู้ใช้ยืนยันตัวตนด้วย Google แล้วระบบจับคู่กับตาราง members ด้วยอีเมล
-- =====================================================================

-- ---------- ตาราง ----------
create table public.members (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique check (email = lower(email)),
  name        text not null,
  role        text not null check (role in ('MD','PM','HEAD','STAFF','ADMIN')),
  dept        text not null default '',
  pos         text not null default '',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table public.projects (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  description text not null default '',
  dept        text not null default '',
  owner_id    uuid not null references public.members(id),
  start_date  date not null,
  due_date    date not null,
  created_at  timestamptz not null default now(),
  check (due_date >= start_date)
);

create table public.tasks (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  description text not null default '',
  creator_id  uuid not null references public.members(id),
  assignee_id uuid not null references public.members(id),
  dept        text not null default '',
  status      text not null default 'todo' check (status in ('todo','doing','blocked','pending','done')),
  start_date  date not null,
  due_date    date not null,
  reason      text not null default '',
  depends_on  uuid references public.tasks(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (due_date >= start_date),
  check (depends_on is null or depends_on <> id)
);

create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks(id) on delete cascade,
  author_id   uuid not null references public.members(id),
  body        text not null check (length(trim(body)) > 0),
  created_at  timestamptz not null default now()
);

create table public.activity_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid references public.members(id),
  text        text not null,
  created_at  timestamptz not null default now()
);

create index on public.projects (owner_id);
create index on public.tasks (project_id);
create index on public.tasks (assignee_id);
create index on public.tasks (creator_id);
create index on public.tasks (depends_on);
create index on public.comments (task_id);
create index on public.comments (author_id);
create index on public.activity_log (actor_id);
create index on public.activity_log (created_at desc);

-- ---------- ฟังก์ชันช่วย (อยู่ใน schema private ที่ API ไม่เปิดให้เรียก) ----------
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.me()
returns public.members
language sql stable security definer set search_path = ''
as $$
  select m.* from public.members m
  where m.email = lower(coalesce(auth.jwt() ->> 'email', ''))
    and m.active
  limit 1
$$;

create or replace function private.me_id()   returns uuid language sql stable security definer set search_path = '' as $$ select (private.me()).id $$;
create or replace function private.me_role() returns text language sql stable security definer set search_path = '' as $$ select (private.me()).role $$;
create or replace function private.me_dept() returns text language sql stable security definer set search_path = '' as $$ select (private.me()).dept $$;

-- ---------- ตรวจสิทธิ์ของ Task (ตรงกับฟังก์ชัน can() ในหน้าเว็บ) ----------
create or replace function private.can_edit_task(t public.tasks)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case private.me_role()
    when 'PM' then true
    when 'ADMIN' then true
    when 'HEAD' then t.dept = private.me_dept()
    when 'STAFF' then t.assignee_id = private.me_id()
    else false end
$$;

create or replace function private.can_confirm_own(t public.tasks)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case private.me_role()
    when 'MD' then true
    when 'PM' then true
    when 'HEAD' then t.assignee_id = private.me_id()
    when 'STAFF' then t.assignee_id = private.me_id()
    else false end
$$;

create or replace function private.can_confirm_sup(t public.tasks)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case private.me_role()
    when 'MD' then true
    when 'PM' then true
    when 'HEAD' then t.dept = private.me_dept()
    else false end
$$;

-- ---------- Trigger: ตรวจการแก้ไข Task ----------
create or replace function private.enforce_task_update()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  is_creator boolean := coalesce(old.creator_id = private.me_id(), false);
  cur uuid;
  guard int := 0;
begin
  -- เปลี่ยนข้อมูลงาน (ไม่ใช่สถานะ) ได้เฉพาะผู้สร้างงาน
  if (new.name, new.description, new.assignee_id, new.dept, new.start_date, new.due_date, new.depends_on, new.project_id, new.creator_id)
     is distinct from
     (old.name, old.description, old.assignee_id, old.dept, old.start_date, old.due_date, old.depends_on, old.project_id, old.creator_id) then
    if not is_creator then
      raise exception 'เฉพาะผู้สร้างงานเท่านั้นที่แก้ไขรายละเอียดงานได้';
    end if;
    if new.project_id <> old.project_id or new.creator_id <> old.creator_id then
      raise exception 'ไม่สามารถย้ายโปรเจคหรือเปลี่ยนผู้สร้างงานได้';
    end if;
  end if;

  -- ตรวจการพึ่งพาที่วนเป็นวงกลม
  if new.depends_on is not null and new.depends_on is distinct from old.depends_on then
    cur := new.depends_on;
    while cur is not null and guard < 200 loop
      if cur = new.id then
        raise exception 'งานที่เลือกทำให้เกิดการพึ่งพาวนเป็นวงกลม';
      end if;
      select depends_on into cur from public.tasks where id = cur;
      guard := guard + 1;
    end loop;
  end if;

  -- ตรวจการเปลี่ยนสถานะ
  if new.status is distinct from old.status then
    if old.status = 'todo' and new.status = 'doing' and private.can_edit_task(old) then null;
    elsif old.status = 'doing' and new.status = 'blocked' and private.can_edit_task(old) then
      if length(trim(new.reason)) = 0 then raise exception 'กรุณาระบุเหตุผลที่ติดขัด'; end if;
    elsif old.status = 'blocked' and new.status = 'doing' and private.can_edit_task(old) then new.reason := '';
    elsif old.status = 'doing' and new.status = 'pending' and private.can_confirm_own(old) then null;
    elsif old.status = 'pending' and new.status = 'done' and private.can_confirm_sup(old) then null;
    elsif old.status = 'pending' and new.status = 'doing' and private.can_confirm_sup(old) then new.reason := '';
    elsif old.status = 'done' and new.status = 'pending' and private.can_confirm_sup(old) then null;
    else
      raise exception 'ไม่มีสิทธิ์เปลี่ยนสถานะจาก % เป็น %', old.status, new.status;
    end if;
  elsif new.reason is distinct from old.reason and not is_creator then
    raise exception 'ไม่มีสิทธิ์แก้ไขเหตุผล';
  end if;

  new.updated_at := now();
  return new;
end $$;

create trigger tasks_enforce_update
before update on public.tasks
for each row execute function private.enforce_task_update();

-- ---------- Trigger: ตรวจการแก้ไขผู้ใช้ ----------
create or replace function private.enforce_member_update()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if coalesce(private.me_role(), '') <> 'ADMIN'
     and (new.email, new.name, new.role, new.dept, new.pos) is distinct from (old.email, old.name, old.role, old.dept, old.pos) then
    raise exception 'เฉพาะแอดมินเท่านั้นที่แก้ไขข้อมูลผู้ใช้ได้';
  end if;
  if old.id = private.me_id() and (new.role <> old.role or new.active = false) then
    raise exception 'ไม่สามารถเปลี่ยนบทบาทหรือปิดการใช้งานบัญชีที่กำลังใช้งานได้';
  end if;
  new.email := lower(trim(new.email));
  return new;
end $$;

create trigger members_enforce_update
before update on public.members
for each row execute function private.enforce_member_update();

-- ---------- Row Level Security ----------
alter table public.members      enable row level security;
alter table public.projects     enable row level security;
alter table public.tasks        enable row level security;
alter table public.comments     enable row level security;
alter table public.activity_log enable row level security;

-- members
create policy "members: อ่านได้เมื่อเป็นสมาชิก" on public.members
  for select to authenticated
  using ((select private.me_id()) is not null or email = lower(coalesce((select auth.jwt()) ->> 'email', '')));
create policy "members: แอดมินเพิ่มผู้ใช้" on public.members
  for insert to authenticated
  with check ((select private.me_role()) = 'ADMIN');
create policy "members: แก้ไขตามบทบาท" on public.members
  for update to authenticated
  using ((select private.me_role()) in ('MD','PM','HEAD','ADMIN'))
  with check ((select private.me_role()) in ('MD','PM','HEAD','ADMIN'));

-- projects
create policy "projects: สมาชิกอ่านได้" on public.projects
  for select to authenticated using ((select private.me_id()) is not null);
create policy "projects: สร้างตามบทบาท" on public.projects
  for insert to authenticated
  with check ((select private.me_role()) in ('MD','PM','HEAD','ADMIN') and owner_id = (select private.me_id()));
create policy "projects: เจ้าของแก้ไข" on public.projects
  for update to authenticated
  using (owner_id = (select private.me_id()))
  with check (owner_id = (select private.me_id()));

-- tasks
create policy "tasks: สมาชิกอ่านได้" on public.tasks
  for select to authenticated using ((select private.me_id()) is not null);
create policy "tasks: สร้างตามบทบาท" on public.tasks
  for insert to authenticated
  with check ((select private.me_role()) in ('PM','HEAD','ADMIN') and creator_id = (select private.me_id()) and status = 'todo');
create policy "tasks: แก้ไขตามสิทธิ์" on public.tasks
  for update to authenticated
  using (
    creator_id = (select private.me_id())
    or (select private.me_role()) in ('MD','PM','ADMIN')
    or ((select private.me_role()) = 'HEAD' and dept = (select private.me_dept()))
    or assignee_id = (select private.me_id())
  );

-- comments
create policy "comments: สมาชิกอ่านได้" on public.comments
  for select to authenticated using ((select private.me_id()) is not null);
create policy "comments: สมาชิกเขียนได้" on public.comments
  for insert to authenticated with check (author_id = (select private.me_id()));

-- activity_log
create policy "log: MD และแอดมินอ่านได้" on public.activity_log
  for select to authenticated using ((select private.me_role()) in ('MD','ADMIN'));
create policy "log: สมาชิกบันทึกได้" on public.activity_log
  for insert to authenticated with check (actor_id = (select private.me_id()));

-- ทำให้อีเมลเป็นตัวพิมพ์เล็กตอนเพิ่มผู้ใช้
create or replace function private.normalize_member_email()
returns trigger language plpgsql set search_path = ''
as $$ begin new.email := lower(trim(new.email)); return new; end $$;
create trigger members_normalize_email before insert on public.members
for each row execute function private.normalize_member_email();

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- ---------- ผู้ดูแลระบบคนแรก ----------
insert into public.members (email, name, role, dept, pos)
values ('narapon002@gmail.com', 'ผู้ดูแลระบบ', 'ADMIN', 'ไอที', 'ผู้ดูแลระบบ')
on conflict (email) do nothing;
