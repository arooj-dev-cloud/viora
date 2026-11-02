# Supabase setup

Create a Supabase project and put its project URL and publishable key in local `.env`. Apply every SQL migration in `supabase/migrations/` in numeric order through `0018_direct_conversation_lock.sql`. This creates the private `status-media` bucket and policies for expiring photo/video Vibes, message muting, support reports, message editing/deletion/reactions, duplicate-safe direct conversation creation, and the other app tables. Do not use a service-role key in the Flutter app.

For password recovery on Android/iOS, add `viora://auth-callback/**` to **Authentication → URL Configuration → Redirect URLs** in the Supabase dashboard. The app registers the `viora://auth-callback` deep link in the Android manifest and iOS URL types. The recovery link opens Viora, Supabase restores the recovery session, and the app presents the new-password form. Web recovery redirects back to the current web origin; add that origin to the redirect allow list when hosting the web app.

Storage buckets and policies must be configured before uploads are enabled. Never place a service-role key in the Flutter app or `.env`.
