-- Keep this migration safe for projects that already applied the first
-- version of 0008_calls.sql before the client-side call-id change.
drop function if exists public.begin_call_session(uuid, uuid, text, jsonb);

create or replace function public.begin_call_session(
  p_call_id uuid,
  p_conversation_id uuid,
  p_callee_id uuid,
  p_media_type text,
  p_offer_sdp jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then raise exception 'Authentication required'; end if;
  if p_media_type not in ('audio', 'video') then raise exception 'Invalid call type'; end if;
  if p_callee_id = caller then raise exception 'You cannot call yourself'; end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'You are not a member of this conversation';
  end if;
  if exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id and c.is_group
  ) or (
    select count(*) from public.conversation_members m
    where m.conversation_id = p_conversation_id
  ) <> 2 then
    raise exception 'Calls are only available in direct conversations';
  end if;
  if not exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = p_callee_id
  ) then raise exception 'The person you selected is not in this conversation'; end if;

  insert into public.call_sessions (
    id, conversation_id, caller_id, callee_id, media_type, offer_sdp
  ) values (
    p_call_id, p_conversation_id, caller, p_callee_id, p_media_type, p_offer_sdp
  );
  return p_call_id;
end;
$$;

revoke all on function public.begin_call_session(uuid, uuid, uuid, text, jsonb) from public;
grant execute on function public.begin_call_session(uuid, uuid, uuid, text, jsonb) to authenticated;

create or replace function public.finish_call_session(p_call_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('rejected', 'ended', 'missed') then
    raise exception 'Invalid call status';
  end if;
  update public.call_sessions
  set status = p_status, ended_at = now()
  where id = p_call_id
    and (caller_id = auth.uid() or callee_id = auth.uid())
    and status in ('ringing', 'accepted');
  if not found then raise exception 'This call is no longer available'; end if;

  if p_status in ('missed', 'rejected') then
    update public.user_notifications
    set body = case
      when p_status = 'rejected' then 'Declined call'
      when (select media_type from public.call_sessions where id = p_call_id) = 'video'
        then 'Missed video call'
      else 'Missed voice call'
    end
    where entity_id = p_call_id
      and recipient_id = (
        select callee_id from public.call_sessions where id = p_call_id
      );
  end if;
end;
$$;

revoke all on function public.finish_call_session(uuid, text) from public;
grant execute on function public.finish_call_session(uuid, text) to authenticated;
