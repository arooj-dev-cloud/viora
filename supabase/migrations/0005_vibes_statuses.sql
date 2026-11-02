create table if not exists public.vibes_statuses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 280),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create index if not exists vibes_statuses_active_idx
  on public.vibes_statuses (expires_at desc, created_at desc);

alter table public.vibes_statuses enable row level security;
grant select, insert, delete on public.vibes_statuses to authenticated;

create or replace function public.is_conversation_member_for_user(other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members member
    where member.user_id = other_user_id
      and exists (
        select 1 from public.conversation_members mine
        where mine.conversation_id = member.conversation_id
          and mine.user_id = auth.uid()
      )
  );
$$;

revoke all on function public.is_conversation_member_for_user(uuid) from public;
grant execute on function public.is_conversation_member_for_user(uuid) to authenticated;

create policy "Read active statuses from your chats"
on public.vibes_statuses for select to authenticated
using (
  expires_at > now()
  and (user_id = auth.uid() or public.is_conversation_member_for_user(user_id))
);

create policy "Users post their own statuses"
on public.vibes_statuses for insert to authenticated
with check (user_id = auth.uid() and expires_at > now() and expires_at <= now() + interval '24 hours 1 minute');

create policy "Users delete their own statuses"
on public.vibes_statuses for delete to authenticated
using (user_id = auth.uid());
