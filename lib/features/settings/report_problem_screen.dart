import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _details = TextEditingController();
  String _category = 'Something is not working';
  bool _sending = false;

  static const _categories = [
    'Something is not working',
    'Account or sign-in',
    'Messages or calls',
    'Vibes or media',
    'Safety concern',
    'Other feedback',
  ];

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (!AppConfig.supabaseConfigured || user == null) {
      _message('Sign in to send a report.');
      return;
    }
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.from('support_reports').insert({
        'user_id': user.id,
        'category': _category,
        'details': _details.text.trim(),
        'app_version': '1.0.0',
      });
      if (!mounted) return;
      _details.clear();
      _message('Report sent. Thanks for helping us improve Viora.');
      Navigator.pop(context);
    } on PostgrestException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('Your report could not be sent. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Report a Problem')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.support_agent, size: 48, color: VioraColors.blush),
            const SizedBox(height: 12),
            const Text(
              'Tell us what happened',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your report is sent privately to the Viora support team.',
              style: TextStyle(color: VioraColors.silver),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'What is this about?',
              ),
              items: _categories
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: _sending
                  ? null
                  : (value) {
                      if (value != null) setState(() => _category = value);
                    },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _details,
              minLines: 5,
              maxLines: 9,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details',
                hintText: 'Describe what happened and how we can reproduce it…',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().length < 10)
                  ? 'Please add at least 10 characters.'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_sending ? 'Sending…' : 'Send Report'),
            ),
          ],
        ),
      ),
    ),
  );
}
