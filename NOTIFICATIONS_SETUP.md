# Notifications setup

Viora uses a `user_notifications` table and Supabase Realtime for in-app alerts, with `flutter_local_notifications` for a local alert while the app is active. Run the ordered Supabase migrations to create the table, row-level policies, message notification trigger, and Realtime publication.

This does not deliver alerts when the app is closed or suspended. Background push needs an operating-system push transport and server credentials; only Supabase Realtime and in-app local alerts are configured at this stage.
