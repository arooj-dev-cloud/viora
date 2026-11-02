// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viora/app.dart';
import 'package:viora/features/home/home_screen.dart';
import 'package:viora/features/notifications/notifications_screen.dart';
import 'package:viora/features/messaging/call_history_screen.dart';
import 'package:viora/features/messaging/saved_messages_screen.dart';
import 'package:viora/features/settings/blocked_users_screen.dart';
import 'package:viora/features/settings/muted_conversations_screen.dart';
import 'package:viora/features/auth/auth_screen.dart';

void main() {
  testWidgets('welcome screen has three swipeable slides and auth actions', (
    tester,
  ) async {
    await tester.pumpWidget(const VioraApp());
    expect(find.text('VIORA'), findsOneWidget);
    expect(find.text('More than\nmessages'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.textContaining('Already have an account?'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Your people,\nyour space'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Same vibes,\nalways'), findsOneWidget);
  });

  testWidgets('Get Started opens the existing signup screen', (tester) async {
    await tester.pumpWidget(const VioraApp());
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('or continue with'), findsNothing);
  });

  testWidgets('Log In opens the existing login and recovery screens', (
    tester,
  ) async {
    await tester.pumpWidget(const VioraApp());
    await tester.tap(find.textContaining('Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('or continue with'), findsNothing);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('Send recovery link'), findsOneWidget);
  });

  testWidgets('onboarding fits small phones and large screens', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpWidget(const VioraApp());
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1200, 1000);
    await tester.pumpWidget(const VioraApp());
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Discover uses the email account lookup flow', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sign in to find Viora users by their account email.'),
      findsOneWidget,
    );
    expect(find.text('Invite friends from contacts'), findsNothing);
  });

  testWidgets('home navigation keeps its four tabs and opens Vibes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('Chats'), findsNWidgets(2));
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Vibes'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.text('Vibes'));
    await tester.pumpAndSettle();
    expect(find.text('Your people, your space.'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vibes explains that sign-in is required', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.tap(find.text('Vibes'));
    await tester.pumpAndSettle();
    expect(find.text('Your people, your space.'), findsOneWidget);
    expect(
      find.text('Sign in to post a Vibe for people you chat with.'),
      findsOneWidget,
    );
  });

  testWidgets('Notification inbox remains usable before backend setup', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see notifications.'), findsOneWidget);
  });

  testWidgets('private account screens explain sign-in without Supabase', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SavedMessagesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see saved messages.'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: CallHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see call history.'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: BlockedUsersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to manage blocked users.'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: MutedConversationsScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to manage muted chats.'), findsOneWidget);
  });

  testWidgets('password reset form is available for a recovered session', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ResetPasswordScreen()));
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('Update Password'), findsOneWidget);
  });
}
