create table if not exists public.support_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in (
    'Something is not working',
    'Account or sign-in',
    'Messages or calls',
    'Vibes or media',
    'Safety concern',
    'Other feedback'
  )),
  details text not null check (char_length(trim(details)) between 10 and 2000),
  app_version text,
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  created_at timestamptz not null default now()
);

create index if not exists support_reports_user_created_idx
  on public.support_reports (user_id, created_at desc);

alter table public.support_reports enable row level security;
grant insert on public.support_reports to authenticated;

create policy "Users submit their own support reports"
on public.support_reports for insert to authenticated
with check (user_id = auth.uid());
