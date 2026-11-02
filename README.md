# Viora

Viora is a Flutter messaging app foundation with a dark plum visual system and a butterfly-led welcome experience.

## Current status

The welcome flow has three responsive onboarding slides with custom-drawn chat mascots. Login, sign-up, password recovery/reset, and saved Supabase sessions use a purple glass-card UI. Direct and group conversations use Supabase Postgres and Realtime, with private image/video attachments, author-only message editing/deletion, emoji reactions, saved messages, shared-media browsing, mute controls, and a persistent Enter-to-send preference. Profile editing, visibility preferences, block/unblock controls, device-local contact invitations, 24-hour text/photo/video Vibes, in-app notifications, one-to-one WebRTC call signaling, missed-call handling, and call history have implementation scaffolding and ordered SQL migrations. Contact invitations use `VIORA_INVITE_URL` from `.env`; its example value is a placeholder that must be replaced before inviting real users.

## Run

1. Install Flutter stable and Android Studio or Xcode for your target platform.
2. Copy `.env.example` to `.env` and enter your Supabase project URL and publishable key.
3. Run `flutter pub get` and `flutter run` from this folder.

The app can show its local UI without configured credentials. Apply every ordered SQL migration before trying messaging, notifications, calls, Vibe media, saved messages, muting, or blocking. Call signaling and history use Supabase; the bundled STUN server is a development default, production calls need protected TURN credentials, and calls still need testing between real devices on different networks. In-app notification records sync through Supabase; background push delivery is not configured. Never put service-role keys in a mobile app. Values bundled into the app are discoverable by users.

## Launcher icon

Place your icon at `assets/icons/viora.png`. For Android adaptive icons, supply a centered foreground mark with transparent padding and a solid background. Regenerate with `dart run flutter_launcher_icons`.
