insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('profile-media', 'profile-media', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('message-attachments', 'message-attachments', false, 26214400, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'audio/mpeg', 'application/pdf']),
  ('status-media', 'status-media', false, 26214400, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Authenticated users read profile pictures"
on storage.objects for select to authenticated
using (bucket_id = 'profile-media');

create policy "Users upload their own profile pictures"
on storage.objects for insert to authenticated
with check (bucket_id = 'profile-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update their own profile pictures"
on storage.objects for update to authenticated
using (bucket_id = 'profile-media' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'profile-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users delete their own profile pictures"
on storage.objects for delete to authenticated
using (bucket_id = 'profile-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Conversation members read their attachments"
on storage.objects for select to authenticated
using (bucket_id = 'message-attachments' and public.is_conversation_member((storage.foldername(name))[1]::uuid));

create policy "Members upload attachments as themselves"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'message-attachments'
  and public.is_conversation_member((storage.foldername(name))[1]::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);

create policy "Owners delete their conversation attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'message-attachments'
  and public.is_conversation_member((storage.foldername(name))[1]::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);

create policy "Users read their own status media"
on storage.objects for select to authenticated
using (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users upload their own status media"
on storage.objects for insert to authenticated
with check (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update their own status media"
on storage.objects for update to authenticated
using (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users delete their own status media"
on storage.objects for delete to authenticated
using (bucket_id = 'status-media' and (storage.foldername(name))[1] = auth.uid()::text);
