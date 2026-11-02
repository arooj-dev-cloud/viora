create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  notification_type text not null check (notification_type in ('message', 'call')),
  title text not null,
  body text not null,
  entity_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists user_notifications_recipient_created_idx
  on public.user_notifications (recipient_id, created_at desc);

alter table public.user_notifications enable row level security;
grant select on public.user_notifications to authenticated;
grant update (read_at) on public.user_notifications to authenticated;

create policy "Users read their own notifications"
on public.user_notifications for select to authenticated
using (recipient_id = auth.uid());

create policy "Users mark their own notifications read"
on public.user_notifications for update to authenticated
using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

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
    and member.user_id <> new.sender_id;
  return new;
end;
$$;

drop trigger if exists on_message_notify_members on public.messages;
create trigger on_message_notify_members
  after insert on public.messages
  for each row execute procedure public.notify_conversation_members_of_message();

do $$
begin
  alter publication supabase_realtime add table public.user_notifications;
exception when duplicate_object then
  null;
end;
$$;
