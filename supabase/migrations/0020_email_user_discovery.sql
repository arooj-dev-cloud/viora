-- Exact-email discovery without granting Flutter direct access to auth.users
-- or exposing account email addresses. Rate limit each signed-in user.
create table if not exists public.email_discovery_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null default (now() at time zone 'utc')::date,
  attempts integer not null default 0 check (attempts >= 0),
  primary key (user_id, usage_day)
);

alter table public.email_discovery_limits enable row level security;
revoke all on public.email_discovery_limits from anon, authenticated;

create or replace function public.find_viora_user_by_email(search_email text)
returns table (id uuid, display_name text, username text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  clean_email text := lower(trim(coalesce(search_email, '')));
  current_day date := (now() at time zone 'utc')::date;
  attempt_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if length(clean_email) > 254 or clean_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return;
  end if;

  insert into public.email_discovery_limits(user_id, usage_day, attempts)
  values (caller_id, current_day, 1)
  on conflict (user_id, usage_day) do update
    set attempts = public.email_discovery_limits.attempts + 1
  returning attempts into attempt_count;

  if attempt_count > 30 then
    raise exception 'Daily email search limit reached. Try again tomorrow.';
  end if;

  return query
  select p.id, p.display_name, p.username
  from auth.users u
  join public.profiles p on p.id = u.id
  where lower(u.email) = clean_email
    and u.id <> caller_id
  limit 1;
end;
$$;

revoke all on function public.find_viora_user_by_email(text) from public, anon;
grant execute on function public.find_viora_user_by_email(text) to authenticated;
