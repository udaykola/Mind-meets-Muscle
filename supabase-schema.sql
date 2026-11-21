-- PROBLEM CRACKERS schema. Run once in Supabase > SQL Editor.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  headline text, phone text, avatar_url text, intro text,
  portfolio_url text, github_url text, linkedin_url text,
  experience text check (experience in ('Beginner','Intermediate','Advanced','Professional')),
  skills text[] not null default '{}',
  roles text[] not null default '{}',          -- idea_owner, developer, business_owner
  is_admin boolean not null default false,
  suspended boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists ideas (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 150),
  description text not null, problem text, solution text,
  skills text[] not null default '{}',
  category text, outcome text, budget text, timeline text, collab_pref text, file_url text,
  status text not null default 'Looking for Team'
    check (status in ('Looking for Team','Collaboration Started','Development in Progress','Completed')),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  name text not null, category text, description text, owner_name text,
  email text, phone text, location text, city text, state text, country text,
  website text, logo_url text,
  needs text[] not null default '{}',
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists collab_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references profiles(id) on delete cascade,
  to_id uuid not null references profiles(id) on delete cascade,
  idea_id uuid references ideas(id) on delete set null,
  business_id uuid references businesses(id) on delete set null,
  message text,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references profiles(id) on delete cascade,
  to_id uuid not null references profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  body text not null, read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists saved_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null check (kind in ('idea','developer','business')),
  item_id uuid not null,
  unique (user_id, kind, item_id)
);

create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles(id) on delete cascade,
  kind text not null, item_id uuid not null, reason text,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);

-- Helper: admin check (security definer avoids RLS recursion)
create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as
$$ select coalesce((select is_admin from profiles where id = auth.uid()), false) $$;

-- Auto-create profile on signup
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name, phone)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), coalesce(new.phone, new.raw_user_meta_data->>'phone'))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Notifications are created by triggers, never by clients
create or replace function notify_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into notifications(user_id, body) values (new.to_id, 'You received a new collaboration request.');
  elsif new.status <> old.status then
    insert into notifications(user_id, body) values (new.from_id, 'Your collaboration request was ' || new.status || '.');
  end if;
  return new;
end $$;
drop trigger if exists trg_notify_request on collab_requests;
create trigger trg_notify_request after insert or update on collab_requests
  for each row execute function notify_request();

create or replace function notify_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications(user_id, body) values (new.to_id, 'You have a new message.');
  return new;
end $$;
drop trigger if exists trg_notify_message on messages;
create trigger trg_notify_message after insert on messages
  for each row execute function notify_message();

-- Row Level Security
alter table profiles enable row level security;
alter table ideas enable row level security;
alter table businesses enable row level security;
alter table collab_requests enable row level security;
alter table messages enable row level security;
alter table notifications enable row level security;
alter table saved_items enable row level security;
alter table reports enable row level security;

create policy "profiles read" on profiles for select to authenticated using (not suspended or id = auth.uid() or is_admin());
create policy "profiles update own" on profiles for update to authenticated using (id = auth.uid() or is_admin());
revoke update on profiles from authenticated;
grant update (full_name, headline, phone, avatar_url, intro, portfolio_url, github_url, linkedin_url, experience, skills, roles) on profiles to authenticated;
-- admins change suspended via the admin_set_suspended function below
create or replace function admin_set_suspended(uid uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not allowed'; end if;
  update profiles set suspended = val where id = uid;
end $$;

create policy "ideas read" on ideas for select to authenticated using (not hidden or owner_id = auth.uid() or is_admin());
create policy "ideas insert" on ideas for insert to authenticated with check (owner_id = auth.uid());
create policy "ideas update" on ideas for update to authenticated using (owner_id = auth.uid() or is_admin());
create policy "ideas delete" on ideas for delete to authenticated using (owner_id = auth.uid() or is_admin());

create policy "biz read" on businesses for select to authenticated using (not hidden or owner_id = auth.uid() or is_admin());
create policy "biz insert" on businesses for insert to authenticated with check (owner_id = auth.uid());
create policy "biz update" on businesses for update to authenticated using (owner_id = auth.uid() or is_admin());
create policy "biz delete" on businesses for delete to authenticated using (owner_id = auth.uid() or is_admin());

create policy "req read" on collab_requests for select to authenticated using (from_id = auth.uid() or to_id = auth.uid() or is_admin());
create policy "req insert" on collab_requests for insert to authenticated with check (from_id = auth.uid());
create policy "req respond" on collab_requests for update to authenticated using (to_id = auth.uid());

create policy "msg read" on messages for select to authenticated using (from_id = auth.uid() or to_id = auth.uid());
create policy "msg insert" on messages for insert to authenticated with check (from_id = auth.uid());

create policy "notif read" on notifications for select to authenticated using (user_id = auth.uid());
create policy "notif update" on notifications for update to authenticated using (user_id = auth.uid());

create policy "saved all" on saved_items for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "report insert" on reports for insert to authenticated with check (reporter_id = auth.uid());
create policy "report admin read" on reports for select to authenticated using (is_admin());
create policy "report admin update" on reports for update to authenticated using (is_admin());

-- Storage bucket for avatars, logos, idea documents (public read, write into own folder)
insert into storage.buckets (id, name, public) values ('uploads','uploads',true) on conflict do nothing;
create policy "uploads read" on storage.objects for select using (bucket_id = 'uploads');
create policy "uploads write own" on storage.objects for insert to authenticated
  with check (bucket_id = 'uploads' and (storage.foldername(name))[1] = auth.uid()::text);

-- Make yourself admin after signing up (replace the email):
-- update profiles set is_admin = true where id = (select id from auth.users where email = 'you@example.com');
