-- Return the latest persisted message metadata for the chat list.
-- Preserve each conversation and all existing message data.
drop function if exists public.list_my_conversations();

create function public.list_my_conversations()
returns table (
  conversation_id uuid,
  display_title text,
  is_group boolean,
  last_message text,
  member_count bigint,
  last_message_at timestamptz,
  last_attachment_path text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    case when c.is_group then coalesce(c.title, 'Group conversation')
      else coalesce(
        (select coalesce(nullif(trim(p.display_name), ''), '@' || coalesce(p.username, 'viora_user'))
         from public.conversation_members peer
         join public.profiles p on p.id = peer.user_id
         where peer.conversation_id = c.id and peer.user_id <> auth.uid()
         limit 1),
        'Viora conversation'
      )
    end,
    c.is_group,
    coalesce(latest.body, 'Start a conversation'),
    (select count(*) from public.conversation_members members where members.conversation_id = c.id),
    latest.created_at,
    latest.attachment_path
  from public.conversations c
  join public.conversation_members mine
    on mine.conversation_id = c.id and mine.user_id = auth.uid()
  left join lateral (
    select message.body, message.created_at, message.attachment_path
    from public.messages message
    where message.conversation_id = c.id
    order by message.created_at desc, message.id desc
    limit 1
  ) latest on true
  where auth.uid() is not null
  order by coalesce(latest.created_at, c.created_at) desc, c.id desc;
$$;

revoke all on function public.list_my_conversations() from public;
grant execute on function public.list_my_conversations() to authenticated;

create index if not exists messages_conversation_created_id_idx
  on public.messages (conversation_id, created_at desc, id desc);
