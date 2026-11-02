create table if not exists public.chat_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  send_on_enter boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.chat_preferences enable row level security;
grant select, insert, update on public.chat_preferences to authenticated;

create policy "Users read their chat preferences"
on public.chat_preferences for select to authenticated
using (user_id = auth.uid());

create policy "Users create their chat preferences"
on public.chat_preferences for insert to authenticated
with check (user_id = auth.uid());

create policy "Users update their chat preferences"
on public.chat_preferences for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
