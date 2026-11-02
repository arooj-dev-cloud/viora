create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('❤️', '😂', '😮', '😢', '👏', '🔥')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.message_reactions enable row level security;
grant select, insert, delete on public.message_reactions to authenticated;
grant update (emoji) on public.message_reactions to authenticated;

create policy "Members read reactions on accessible messages"
on public.message_reactions for select to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id
      and public.is_conversation_member(m.conversation_id)
  )
);

create policy "Users react as themselves to accessible messages"
on public.message_reactions for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id
      and public.is_conversation_member(m.conversation_id)
  )
);

create policy "Users remove their own reactions"
on public.message_reactions for delete to authenticated
using (user_id = auth.uid());

create policy "Users change their own reactions"
on public.message_reactions for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id
      and public.is_conversation_member(m.conversation_id)
  )
);

do $$
begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then
  null;
end;
$$;
