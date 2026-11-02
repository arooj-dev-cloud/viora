-- Serialize concurrent attempts to open the same direct conversation.
-- The lock key is derived from the sorted pair so both participants lock the
-- same transaction key regardless of who initiates the chat.
create or replace function public.open_direct_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  conversation_id uuid;
  pair_key text;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if other_user_id is null or other_user_id = caller_id then
    raise exception 'Choose another Viora user';
  end if;
  if not exists (select 1 from public.profiles p where p.id = other_user_id) then
    raise exception 'Viora user not found';
  end if;

  pair_key := least(caller_id::text, other_user_id::text)
    || ':' || greatest(caller_id::text, other_user_id::text);
  perform pg_advisory_xact_lock(hashtextextended(pair_key, 0));

  select c.id into conversation_id
  from public.conversations c
  where not c.is_group
    and exists (
      select 1 from public.conversation_members m
      where m.conversation_id = c.id and m.user_id = caller_id
    )
    and exists (
      select 1 from public.conversation_members m
      where m.conversation_id = c.id and m.user_id = other_user_id
    )
    and (
      select count(*) from public.conversation_members m
      where m.conversation_id = c.id
    ) = 2
  order by c.created_at
  limit 1;

  if conversation_id is null then
    insert into public.conversations (is_group, created_by)
    values (false, caller_id) returning id into conversation_id;
    insert into public.conversation_members (conversation_id, user_id)
    values (conversation_id, caller_id), (conversation_id, other_user_id);
  end if;

  return conversation_id;
end;
$$;

revoke all on function public.open_direct_conversation(uuid) from public;
grant execute on function public.open_direct_conversation(uuid) to authenticated;
