-- Roles
create type public.app_role as enum ('admin', 'user');

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  unique (user_id, role)
);
grant select on public.user_roles to authenticated;
grant all on public.user_roles to service_role;
alter table public.user_roles enable row level security;
create policy "Users read own roles" on public.user_roles for select to authenticated using (auth.uid() = user_id);

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
$$;

-- Profiles
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  phone text,
  invite_code text not null unique,
  referred_by text,
  level integer not null default 1,
  balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
grant select, insert, update on public.profiles to authenticated;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;
create policy "Users read own profile" on public.profiles for select to authenticated using (auth.uid() = id);
create policy "Users update own profile" on public.profiles for update to authenticated using (auth.uid() = id);
create policy "Admins read all profiles" on public.profiles for select to authenticated using (public.has_role(auth.uid(), 'admin'));

-- Vehicles owned by users
create table public.user_vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  region text not null,
  daily text not null,
  return_value text not null,
  price text not null,
  cycle text not null,
  image_key text not null,
  plate text not null,
  purchased_at timestamptz not null default now()
);
grant select, insert, update, delete on public.user_vehicles to authenticated;
grant all on public.user_vehicles to service_role;
alter table public.user_vehicles enable row level security;
create policy "Users read own vehicles" on public.user_vehicles for select to authenticated using (auth.uid() = user_id);
create policy "Users insert own vehicles" on public.user_vehicles for insert to authenticated with check (auth.uid() = user_id);
create policy "Users delete own vehicles" on public.user_vehicles for delete to authenticated using (auth.uid() = user_id);
create policy "Admins read all vehicles" on public.user_vehicles for select to authenticated using (public.has_role(auth.uid(), 'admin'));

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, phone, invite_code, referred_by)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'phone',
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    new.raw_user_meta_data ->> 'referred_by'
  )
  on conflict (id) do nothing;
  insert into public.user_roles (user_id, role) values (new.id, 'user') on conflict do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
