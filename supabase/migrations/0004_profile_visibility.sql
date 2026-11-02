drop policy if exists "Profiles are readable by authenticated users" on public.profiles;
create policy "Users read their own profile row"
on public.profiles for select to authenticated
using (id = auth.uid());

-- The view is owned by the migration role; it deliberately returns only safe
-- profile fields and applies photo/about visibility before exposing them.
create or replace view public.discoverable_profiles
with (security_barrier = true)
as
select
  p.id,
  p.display_name,
  p.username,
  case
    when p.id = auth.uid() or coalesce(s.profile_photo_visibility, 'Everyone') = 'Everyone'
      or (coalesce(s.profile_photo_visibility, 'Everyone') = 'My Contacts' and exists (
        select 1 from public.conversation_members peer
        where peer.user_id = p.id and public.is_conversation_member(peer.conversation_id)
      ))
    then p.avatar_path else null
  end as avatar_path,
  case
    when p.id = auth.uid() or coalesce(s.about_visibility, 'Everyone') = 'Everyone'
      or (coalesce(s.about_visibility, 'Everyone') = 'My Contacts' and exists (
        select 1 from public.conversation_members peer
        where peer.user_id = p.id and public.is_conversation_member(peer.conversation_id)
      ))
    then p.bio else ''
  end as bio
from public.profiles p
left join public.privacy_settings s on s.user_id = p.id
where p.id = auth.uid()
   or coalesce(s.about_visibility, 'Everyone') = 'Everyone'
   or (coalesce(s.about_visibility, 'Everyone') = 'My Contacts' and exists (
     select 1 from public.conversation_members peer
     where peer.user_id = p.id and public.is_conversation_member(peer.conversation_id)
   ));

grant select on public.discoverable_profiles to authenticated;
