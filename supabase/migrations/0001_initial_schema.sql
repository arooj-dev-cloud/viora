 create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  username text unique,
  bio text not null default '',
  avatar_path text,
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  body text not null default '',
  attachment_path text,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at desc);
create index if not exists conversation_members_user_idx
  on public.conversation_members (user_id, conversation_id);

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert on public.conversations to authenticated;
grant select on public.conversation_members to authenticated;
grant select, insert on public.messages to authenticated;

create or replace function public.is_conversation_member(candidate_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = candidate_conversation and m.user_id = auth.uid()
  );
$$;

create or replace function public.open_direct_conversation(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  conversation_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if other_user_id is null or other_user_id = caller_id then
    raise exception 'Choose another Viora user';
  end if;
  if not exists (select 1 from public.profiles p where p.id = other_user_id) then
    raise exception 'Viora user not found';
  end if;

  select c.id into conversation_id
  from public.conversations c
  where not c.is_group
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = caller_id)
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = other_user_id)
    and (select count(*) from public.conversation_members m where m.conversation_id = c.id) = 2
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

create or replace function public.create_group_conversation(group_title text, member_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  conversation_id uuid;
  chosen_members uuid[];
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if group_title is null or length(trim(group_title)) = 0 then
    raise exception 'Enter a group name';
  end if;
  select array_agg(distinct members.user_id) into chosen_members
  from unnest(coalesce(member_ids, array[]::uuid[]) || array[caller_id]) as members(user_id)
  where members.user_id is not null;
  if cardinality(chosen_members) < 2 then raise exception 'Add at least one other member'; end if;
  if cardinality(chosen_members) > 100 then raise exception 'Groups can have at most 100 members'; end if;
  if exists (select 1 from unnest(chosen_members) u(id) left join public.profiles p on p.id = u.id where p.id is null) then
    raise exception 'A selected Viora user was not found';
  end if;

  insert into public.conversations (is_group, title, created_by)
  values (true, trim(group_title), caller_id) returning id into conversation_id;
  insert into public.conversation_members (conversation_id, user_id)
  select conversation_id, members.user_id from unnest(chosen_members) as members(user_id);
  return conversation_id;
end;
$$;

create or replace function public.list_my_conversations()
returns table (
  conversation_id uuid,
  display_title text,
  is_group boolean,
  last_message text,
  member_count bigint
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
    (select count(*) from public.conversation_members members where members.conversation_id = c.id)
  from public.conversations c
  join public.conversation_members mine on mine.conversation_id = c.id and mine.user_id = auth.uid()
  left join lateral (
    select message.body from public.messages message
    where message.conversation_id = c.id
    order by message.created_at desc limit 1
  ) latest on true
  where auth.uid() is not null
  order by coalesce(
    (select max(message.created_at) from public.messages message where message.conversation_id = c.id),
    c.created_at
  ) desc;
$$;

revoke all on function public.open_direct_conversation(uuid) from public;
revoke all on function public.create_group_conversation(text, uuid[]) from public;
revoke all on function public.list_my_conversations() from public;
revoke all on function public.is_conversation_member(uuid) from public;
grant execute on function public.open_direct_conversation(uuid) to authenticated;
grant execute on function public.create_group_conversation(text, uuid[]) to authenticated;
grant execute on function public.list_my_conversations() to authenticated;
grant execute on function public.is_conversation_member(uuid) to authenticated;

create policy "Profiles are readable by authenticated users" on public.profiles for select to authenticated using (true);
create policy "Users create their own profile" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "Users update their own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "Members can read conversations" on public.conversations for select to authenticated using (public.is_conversation_member(id));
create policy "Authenticated users create conversations" on public.conversations for insert to authenticated with check (created_by = auth.uid());
create policy "Members read member rows" on public.conversation_members for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "Conversation members read messages" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id));
create policy "Members send their own messages" on public.messages for insert to authenticated with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id));

do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then
  null;
end;
$$;
