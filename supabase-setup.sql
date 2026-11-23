create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    name text not null,
    email text not null,
    gender text not null default '',
    country text not null default '',
    city text not null default '',
    address text not null default '',
    phone text not null default '',
    photo_path text,
    is_public boolean not null default false,
    created_at timestamptz not null default now()
);

create table if not exists public.student_academic_records (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    level text not null check (level in ('junior', 'graduation')),
    details jsonb not null,
    event_type text not null,
    created_at timestamptz not null default now()
);

create index if not exists student_academic_records_user_created_idx
    on public.student_academic_records (user_id, created_at desc);

alter table public.profiles
    add column if not exists phone text not null default '';

create table if not exists public.admin_users (
    user_id uuid primary key references auth.users (id) on delete cascade
);

alter table public.profiles enable row level security;
alter table public.admin_users enable row level security;
alter table public.student_academic_records enable row level security;

grant select, insert, update, delete on public.profiles to authenticated;
grant select on public.admin_users to authenticated;
revoke all on public.student_academic_records from anon, public, authenticated;
grant select, insert on public.student_academic_records to authenticated;

drop policy if exists "Owners read own academic records" on public.student_academic_records;
create policy "Owners read own academic records"
    on public.student_academic_records for select
    to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "Owners insert own academic records" on public.student_academic_records;
create policy "Owners insert own academic records"
    on public.student_academic_records for insert
    to authenticated
    with check (user_id = (select auth.uid()));

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.admin_users
        where user_id = (select auth.uid())
    );
$$;

revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

drop policy if exists "Owners and admins read profiles" on public.profiles;
create policy "Owners and admins read profiles"
    on public.profiles for select
    to authenticated
    using (id = (select auth.uid()) or (select public.is_site_admin()));

drop policy if exists "Owners insert own profile" on public.profiles;
create policy "Owners insert own profile"
    on public.profiles for insert
    to authenticated
    with check (id = (select auth.uid()));

drop policy if exists "Owners update own profile" on public.profiles;
create policy "Owners update own profile"
    on public.profiles for update
    to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

drop policy if exists "Owners and admins remove profiles" on public.profiles;
create policy "Owners and admins remove profiles"
    on public.profiles for delete
    to authenticated
    using (id = (select auth.uid()) or (select public.is_site_admin()));

drop policy if exists "Users read own admin status" on public.admin_users;
create policy "Users read own admin status"
    on public.admin_users for select
    to authenticated
    using (user_id = (select auth.uid()));

create or replace function public.get_public_profile(profile_id uuid)
returns table (
    id uuid,
    name text,
    email text,
    gender text,
    country text,
    city text,
    address text,
    photo_path text
)
language sql
stable
security definer
set search_path = ''
as $$
    select p.id, p.name, p.email, p.gender, p.country, p.city, p.address, p.photo_path
    from public.profiles as p
    where p.id = profile_id and p.is_public;
$$;

revoke all on function public.get_public_profile(uuid) from public;
grant execute on function public.get_public_profile(uuid) to anon, authenticated;

create or replace function public.list_public_profiles_for_admin()
returns table (id uuid, name text)
language sql
stable
security invoker
set search_path = ''
as $$
    select p.id, p.name
    from public.profiles as p
    where p.is_public and (select public.is_site_admin())
    order by p.name;
$$;

revoke all on function public.list_public_profiles_for_admin() from public;
grant execute on function public.list_public_profiles_for_admin() to authenticated;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from auth.users where id = (select auth.uid());
end;
$$;

create or replace function public.delete_account_as_admin(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not (select public.is_site_admin()) then
        raise exception 'Administrator access is required.';
    end if;
    delete from auth.users where id = target_user_id;
end;
$$;

revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_account_as_admin(uuid) from public;
grant execute on function public.delete_own_account() to authenticated;
grant execute on function public.delete_account_as_admin(uuid) to authenticated;

create or replace function public.sync_auth_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (
        id, name, email, gender, country, city, address, phone, is_public
    )
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'name', ''),
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data ->> 'gender', ''),
        coalesce(new.raw_user_meta_data ->> 'country', ''),
        coalesce(new.raw_user_meta_data ->> 'city', ''),
        coalesce(new.raw_user_meta_data ->> 'address', ''),
        coalesce(new.raw_user_meta_data ->> 'phone', ''),
        new.email_confirmed_at is not null
    )
    on conflict (id) do update set
        name = excluded.name,
        email = excluded.email,
        gender = excluded.gender,
        country = excluded.country,
        city = excluded.city,
        address = excluded.address,
        phone = excluded.phone,
        is_public = excluded.is_public;
    return new;
end;
$$;

drop trigger if exists sync_auth_profile on auth.users;
create trigger sync_auth_profile
    after insert or update on auth.users
    for each row execute function public.sync_auth_profile();

insert into public.profiles (
    id, name, email, gender, country, city, address, phone, is_public
)
select
    u.id,
    coalesce(u.raw_user_meta_data ->> 'name', ''),
    coalesce(u.email, ''),
    coalesce(u.raw_user_meta_data ->> 'gender', ''),
    coalesce(u.raw_user_meta_data ->> 'country', ''),
    coalesce(u.raw_user_meta_data ->> 'city', ''),
    coalesce(u.raw_user_meta_data ->> 'address', ''),
    coalesce(u.raw_user_meta_data ->> 'phone', ''),
    u.email_confirmed_at is not null
from auth.users as u
on conflict (id) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'profile-photos',
    'profile-photos',
    true,
    1572864,
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public can view profile photos" on storage.objects;
create policy "Public can view profile photos"
    on storage.objects for select
    to anon, authenticated
    using (bucket_id = 'profile-photos');

drop policy if exists "Users upload own profile photos" on storage.objects;
create policy "Users upload own profile photos"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'profile-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "Users update own profile photos" on storage.objects;
create policy "Users update own profile photos"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'profile-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id = 'profile-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "Users delete own profile photos" on storage.objects;
create policy "Users delete own profile photos"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'profile-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "Admins delete profile photos" on storage.objects;
create policy "Admins delete profile photos"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'profile-photos'
        and (select public.is_site_admin())
    );

-- After registering and confirming the administrator account, run this separately:
-- insert into public.admin_users (user_id)
-- select id from auth.users where email = 'ADMIN_EMAIL';
