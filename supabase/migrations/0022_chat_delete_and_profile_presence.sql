-- Delete a chat from one user's list without erasing the other participant's
-- history. A later message makes the conversation visible again.
create table if not exists public.hidden_conversations (
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

alter table public.hidden_conversations enable row level security;
revoke all on public.hidden_conversations from anon, authenticated;

create or replace function publi    c.hide_conversation_for_me(target_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found';
  end if;
  insert into public.hidden_conversations(user_id, conversation_id, hidden_at)
  values (auth.uid(), target_conversation_id, now())
  on conflict (user_id, conversation_id) do update set hidden_at = excluded.hidden_at;
end;
$$;

revoke all on function public.hide_conversation_for_me(uuid) from public, anon;
grant execute on function public.hide_conversation_for_me(uuid) to authenticated;

drop function if exists public.list_my_conversations();
create function public.list_my_conversations()
returns table (
  conversation_id uuid,
  display_title text,
  is_group boolean,
  last_message text,
  member_count bigint,
  last_message_at timestamptz,
  last_attachment_path text,
  peer_user_id uuid,
  peer_avatar_path text,
  has_active_vibe boolean
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
    latest.attachment_path,
    (select peer.user_id from public.conversation_members peer
      where peer.conversation_id = c.id and peer.user_id <> auth.uid() limit 1),
    (select p.avatar_path from public.conversation_members peer
      join public.discoverable_profiles p on p.id = peer.user_id
      where peer.conversation_id = c.id and peer.user_id <> auth.uid() limit 1),
    exists (
      select 1 from public.vibes_statuses status
      join public.conversation_members peer on peer.user_id = status.user_id
        and peer.conversation_id = c.id and peer.user_id <> auth.uid()
      where not c.is_group and status.expires_at > now()
    )
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
    and not exists (
      select 1 from public.hidden_conversations hidden
      where hidden.user_id = auth.uid()
        and hidden.conversation_id = c.id
        and hidden.hidden_at >= coalesce(latest.created_at, c.created_at)
    )
  order by coalesce(latest.created_at, c.created_at) desc, c.id desc;
$$;

revoke all on function public.list_my_conversations() from public;
grant execute on function public.list_my_conversations() to authenticated;
