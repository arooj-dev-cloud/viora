alter table public.vibes_statuses
  add column if not exists media_path text,
  add column if not exists media_type text;

alter table public.vibes_statuses alter column body drop not null;
alter table public.vibes_statuses drop constraint if exists vibes_statuses_body_check;
alter table public.vibes_statuses drop constraint if exists vibes_statuses_body_or_media_check;
alter table public.vibes_statuses
  add constraint vibes_statuses_body_or_media_check check (
    (media_path is null and media_type is null and body is not null
      and length(trim(body)) between 1 and 280)
    or
    (media_path is not null and media_type is not null
      and media_type in ('image', 'video')
      and (body is null or length(trim(body)) <= 280))
  );

create policy "Chat peers read active Vibe media"
on storage.objects for select to authenticated
using (
  bucket_id = 'status-media'
  and exists (
    select 1 from public.vibes_statuses status
    where status.media_path = storage.objects.name
      and status.expires_at > now()
      and public.is_conversation_member_for_user(status.user_id)
  )
);
