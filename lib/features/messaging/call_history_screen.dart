import 'package:flutter/material.dart';

import 'calls_tab.dart';

/// Full-screen version of the call log (opened from Settings). The same log
/// is also available as the "Calls" tab on the home screen.
class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Call History')),
    body: const CallsTab(),
  );
}
