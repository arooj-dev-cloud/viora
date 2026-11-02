create table if not exists public.saved_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, message_id)
);

create index if not exists saved_messages_user_created_idx
  on public.saved_messages (user_id, created_at desc);

alter table public.saved_messages enable row level security;
grant select, insert, delete on public.saved_messages to authenticated;

create policy "Users read their saved messages"
on public.saved_messages for select to authenticated
using (user_id = auth.uid());

create policy "Users save messages they can access"
on public.saved_messages for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.is_conversation_member(m.conversation_id)
  )
);

create policy "Users remove their saved messages"
on public.saved_messages for delete to authenticated
using (user_id = auth.uid());
