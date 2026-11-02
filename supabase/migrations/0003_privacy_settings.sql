create table if not exists public.privacy_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_visibility text not null default 'Everyone' check (last_seen_visibility in ('Everyone', 'My Contacts', 'Nobody')),
  profile_photo_visibility text not null default 'Everyone' check (profile_photo_visibility in ('Everyone', 'My Contacts', 'Nobody')),
  about_visibility text not null default 'Everyone' check (about_visibility in ('Everyone', 'My Contacts', 'Nobody')),
  read_receipts boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.privacy_settings enable row level security;
grant select, insert, update on public.privacy_settings to authenticated;

create policy "Users read their privacy settings"
on public.privacy_settings for select to authenticated
using (user_id = auth.uid());

create policy "Users create their privacy settings"
on public.privacy_settings for insert to authenticated
with check (user_id = auth.uid());

create policy "Users update their privacy settings"
on public.privacy_settings for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
