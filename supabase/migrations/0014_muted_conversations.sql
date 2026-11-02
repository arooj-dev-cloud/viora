create table if not exists public.muted_conversations (
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

alter table public.muted_conversations enable row level security;
grant select, insert, delete on public.muted_conversations to authenticated;

create policy "Users read their muted conversations"
on public.muted_conversations for select to authenticated
using (user_id = auth.uid());

create policy "Users mute conversations they belong to"
on public.muted_conversations for insert to authenticated
with check (
  user_id = auth.uid()
  and public.is_conversation_member(conversation_id)
);

create policy "Users unmute their conversations"
on public.muted_conversations for delete to authenticated
using (user_id = auth.uid());

create or replace function public.notify_conversation_members_of_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_name text;
  conversation_name text;
begin
  select coalesce(nullif(trim(p.display_name), ''), 'Viora user')
    into sender_name
  from public.profiles p where p.id = new.sender_id;
  select c.title into conversation_name
  from public.conversations c where c.id = new.conversation_id;

  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, title, body, entity_id
  )
  select
    member.user_id,
    new.sender_id,
    'message',
    coalesce(conversation_name, sender_name),
    case when length(trim(new.body)) = 0 then 'Sent an attachment' else left(new.body, 180) end,
    new.conversation_id
  from public.conversation_members member
  where member.conversation_id = new.conversation_id
    and member.user_id <> new.sender_id
    and not exists (
      select 1 from public.muted_conversations muted
      where muted.user_id = member.user_id
        and muted.conversation_id = new.conversation_id
    );
  return new;
end;
$$;
