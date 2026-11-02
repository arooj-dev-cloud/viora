create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index if not exists blocked_users_blocked_id_idx
  on public.blocked_users (blocked_id, blocker_id);

alter table public.blocked_users enable row level security;
grant select, insert, delete on public.blocked_users to authenticated;

create policy "Participants can see their block relationship"
on public.blocked_users for select to authenticated
using (blocker_id = auth.uid() or blocked_id = auth.uid());

create policy "Users create their own blocks"
on public.blocked_users for insert to authenticated
with check (blocker_id = auth.uid() and blocked_id <> auth.uid());

create policy "Users remove their own blocks"
on public.blocked_users for delete to authenticated
using (blocker_id = auth.uid());

drop policy if exists "Conversation members read messages" on public.messages;
create policy "Conversation members read unblocked messages"
on public.messages for select to authenticated
using (
  public.is_conversation_member(conversation_id)
  and not exists (
    select 1
    from public.conversations c
    join public.conversation_members peer
      on peer.conversation_id = c.id and peer.user_id <> auth.uid()
    join public.blocked_users b
      on (b.blocker_id = auth.uid() and b.blocked_id = peer.user_id)
      or (b.blocker_id = peer.user_id and b.blocked_id = auth.uid())
    where c.id = messages.conversation_id and not c.is_group
  )
);

drop policy if exists "Members send their own messages" on public.messages;
create policy "Members send their own messages unless blocked"
on public.messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id)
  and not exists (
    select 1
    from public.conversations c
    join public.conversation_members peer
      on peer.conversation_id = c.id and peer.user_id <> auth.uid()
    join public.blocked_users b
      on (b.blocker_id = auth.uid() and b.blocked_id = peer.user_id)
      or (b.blocker_id = peer.user_id and b.blocked_id = auth.uid())
    where c.id = messages.conversation_id and not c.is_group
  )
);
