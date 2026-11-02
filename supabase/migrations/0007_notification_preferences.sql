create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  local_alerts_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;
grant select, insert, update on public.notification_preferences to authenticated;

create policy "Users read their notification preferences"
on public.notification_preferences for select to authenticated
using (user_id = auth.uid());

create policy "Users create their notification preferences"
on public.notification_preferences for insert to authenticated
with check (user_id = auth.uid());

create policy "Users update their notification preferences"
on public.notification_preferences for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
