import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/viora_theme.dart';
import '../../data/repositories/messaging_repository.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _selected = <String>{};
  Future<List<Map<String, dynamic>>>? _people;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a group name.');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Choose at least one person to add.');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final id = await MessagingRepository(
        Supabase.instance.client,
      ).createGroup(_name.text, _selected.toList());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: id,
            title: _name.text.trim(),
            isGroup: true,
            memberCount: _selected.length + 1,
          ),
        ),
      );
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create the group. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Group')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group name',
            prefixIcon: Icon(Icons.groups_outlined),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _search,
          onChanged: (query) => setState(() {
            _people = query.trim().isEmpty
                ? null
                : MessagingRepository(
                    Supabase.instance.client,
                  ).searchPeople(query);
          }),
          decoration: const InputDecoration(
            labelText: 'Add people by Viora email',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${_selected.length} selected',
            style: const TextStyle(color: VioraColors.blush),
          ),
        ],
        const SizedBox(height: 10),
        if (_people != null)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _people,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('People could not be loaded. Try again.');
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: [
                  for (final person in snapshot.data!)
                    CheckboxListTile(
                      value: _selected.contains(person['id']),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(person['id'] as String);
                        } else {
                          _selected.remove(person['id']);
                        }
                      }),
                      secondary: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(
                        (person['display_name'] as String?)
                                    ?.trim()
                                    .isNotEmpty ==
                                true
                            ? person['display_name'] as String
                            : 'Viora user',
                      ),
                      subtitle: Text('@${person['username'] ?? 'viora_user'}'),
                      activeColor: VioraColors.blush,
                    ),
                ],
              );
            },
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Enter each person’s exact Viora account email, then choose who to add.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VioraColors.silver),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.pinkAccent)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _creating ? null : _create,
            style: FilledButton.styleFrom(backgroundColor: VioraColors.mauve),
            child: _creating
                ? const CircularProgressIndicator()
                : const Text('Create Group'),
          ),
        ),
      ],
    ),
  );
}
