-- Run once in Supabase Dashboard > SQL Editor.
-- Adds: "delete for me", story "seen" tracking.

-- 1) Delete for me ---------------------------------------------------------
create table if not exists public.message_deletions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  deleted_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.message_deletions enable row level security;
drop policy if exists "own deletions select" on public.message_deletions;
drop policy if exists "own deletions insert" on public.message_deletions;
create policy "own deletions select" on public.message_deletions
  for select using (user_id = auth.uid());
create policy "own deletions insert" on public.message_deletions
  for insert with check (user_id = auth.uid());

-- 2) Story views (removes the green ring once seen) ------------------------
create table if not exists public.vibe_views (
  status_id uuid not null references public.vibes_statuses(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);
alter table public.vibe_views enable row level security;
drop policy if exists "own views select" on public.vibe_views;
drop policy if exists "own views insert" on public.vibe_views;
create policy "own views select" on public.vibe_views
  for select using (viewer_id = auth.uid());
create policy "own views insert" on public.vibe_views
  for insert with check (viewer_id = auth.uid());

-- 3) Realtime for the new tables ------------------------------------------
alter publication supabase_realtime add table public.message_deletions;

-- 4) Voice messages: the existing 'message-attachments' bucket must allow
--    audio/mp4 (.m4a). If you set allowed MIME types on the bucket, add it:
-- update storage.buckets
--   set allowed_mime_types = array_append(allowed_mime_types, 'audio/mp4')
--   where id = 'message-attachments';
