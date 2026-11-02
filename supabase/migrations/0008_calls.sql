create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  caller_id uuid not null references auth.users(id) on delete cascade,
  callee_id uuid not null references auth.users(id) on delete cascade,
  media_type text not null check (media_type in ('audio', 'video')),
  status text not null default 'ringing'
    check (status in ('ringing', 'accepted', 'rejected', 'ended', 'missed')),
  offer_sdp jsonb not null,
  answer_sdp jsonb,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  ended_at timestamptz,
  check (caller_id <> callee_id)
);

create index if not exists call_sessions_callee_status_idx
  on public.call_sessions (callee_id, status, created_at desc);

create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.call_sessions(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  candidate jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists call_signals_call_created_idx
  on public.call_signals (call_id, created_at);

alter table public.call_sessions enable row level security;
alter table public.call_signals enable row level security;
grant select on public.call_sessions to authenticated;
grant select, insert on public.call_signals to authenticated;

create policy "Call participants read their sessions"
on public.call_sessions for select to authenticated
using (caller_id = auth.uid() or callee_id = auth.uid());

create policy "Call participants read their ICE signals"
on public.call_signals for select to authenticated
using (exists (
  select 1 from public.call_sessions c
  where c.id = call_id and (c.caller_id = auth.uid() or c.callee_id = auth.uid())
));

create policy "Participants send their ICE signals"
on public.call_signals for insert to authenticated
with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.call_sessions c
    where c.id = call_id and (c.caller_id = auth.uid() or c.callee_id = auth.uid())
  )
);

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
  call_id uuid;
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
  ) returning id into call_id;
  return call_id;
end;
$$;

create or replace function public.answer_call_session(p_call_id uuid, p_answer_sdp jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.call_sessions
  set status = 'accepted', answer_sdp = p_answer_sdp, accepted_at = now()
  where id = p_call_id and callee_id = auth.uid() and status = 'ringing';
  if not found then raise exception 'This call is no longer available'; end if;
end;
$$;

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

revoke all on function public.begin_call_session(uuid, uuid, uuid, text, jsonb) from public;
revoke all on function public.answer_call_session(uuid, jsonb) from public;
revoke all on function public.finish_call_session(uuid, text) from public;
grant execute on function public.begin_call_session(uuid, uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.answer_call_session(uuid, jsonb) to authenticated;
grant execute on function public.finish_call_session(uuid, text) to authenticated;

create or replace function public.notify_callee_of_call()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_name text;
begin
  select coalesce(nullif(trim(display_name), ''), 'Viora user') into caller_name
  from public.profiles where id = new.caller_id;
  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, title, body, entity_id
  ) values (
    new.callee_id, new.caller_id, 'call', caller_name,
    case when new.media_type = 'video' then 'Incoming video call' else 'Incoming voice call' end,
    new.id
  );
  return new;
end;
$$;

drop trigger if exists on_call_notify_callee on public.call_sessions;
create trigger on_call_notify_callee
  after insert on public.call_sessions
  for each row execute procedure public.notify_callee_of_call();

do $$
begin
  alter publication supabase_realtime add table public.call_sessions;
exception when duplicate_object then
  null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.call_signals;
exception when duplicate_object then
  null;
end;
$$;
