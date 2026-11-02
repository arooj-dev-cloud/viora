import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/viora_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _avatarPath;
  String? _avatarUrl;
  String? _error;

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = _userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to edit your profile.';
      });
      return;
    }
    try {
      final profile = await _client
          .from('profiles')
          .select('display_name,username,bio,avatar_path')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted) return;
      if (profile != null) {
        _name.text = profile['display_name'] as String? ?? '';
        _username.text = profile['username'] as String? ?? '';
        _bio.text = profile['bio'] as String? ?? '';
        _avatarPath = profile['avatar_path'] as String?;
        if (_avatarPath != null) {
          _avatarUrl = await _client.storage
              .from('profile-media')
              .createSignedUrl(_avatarPath!, 3600);
        }
      }
    } on PostgrestException catch (error) {
      if (mounted) _error = error.message;
    } catch (_) {
      if (mounted) {
        _error = 'Profile could not be loaded. Check your connection.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = _userId;
    if (userId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.from('profiles').upsert({
        'id': userId,
        'display_name': _name.text.trim(),
        'username': _username.text.trim().toLowerCase(),
        'bio': _bio.text.trim(),
        'avatar_path': _avatarPath,
      });
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = error.code == '23505'
            ? 'That username is already taken.'
            : error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Profile could not be saved. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final userId = _userId;
    if (userId == null || _uploading) return;
    try {
      final file = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 88);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        setState(() => _error = 'Choose an image smaller than 10 MB.');
        return;
      }
      final extension = file.name.split('.').last.toLowerCase();
      const mimeTypes = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp'
      };
      final mimeType = mimeTypes[extension];
      if (mimeType == null) {
        setState(() => _error = 'Choose a JPG, PNG, or WebP image.');
        return;
      }
      setState(() {
        _uploading = true;
        _error = null;
      });
      final path = '$userId/${const Uuid().v4()}.$extension';
      await _client.storage.from('profile-media').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType),
          );
      await _client
          .from('profiles')
          .update({'avatar_path': path}).eq('id', userId);
      final signedUrl = await _client.storage
          .from('profile-media')
          .createSignedUrl(path, 3600);
      if (mounted) {
        setState(() {
          _avatarPath = path;
          _avatarUrl = signedUrl;
        });
      }
    } on StorageException catch (error) {
      if (mounted) {
        setState(() => _error = 'Avatar upload failed: ${error.message}');
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not choose or upload that image.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: VioraColors.mauve,
                            backgroundImage: _avatarUrl == null
                                ? null
                                : NetworkImage(_avatarUrl!),
                            child: _avatarUrl != null
                                ? null
                                : const Icon(Icons.person_outline, size: 44),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filled(
                              tooltip: 'Choose profile photo',
                              onPressed: _uploading ? null : _pickAvatar,
                              style: IconButton.styleFrom(
                                  backgroundColor: VioraColors.mauve),
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.camera_alt_outlined,
                                      size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text('Display Name'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a display name.'
                              : null,
                      decoration:
                          const InputDecoration(hintText: 'How people see you'),
                    ),
                    const SizedBox(height: 18),
                    const Text('Username'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      validator: (value) {
                        final clean = value?.trim() ?? '';
                        if (clean.isEmpty) return 'Choose a username.';
                        if (!RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(clean)) {
                          return 'Use 3–24 letters, numbers, or underscores.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                          prefixText: '@', hintText: 'choose_username'),
                    ),
                    const SizedBox(height: 18),
                    const Text('Bio'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _bio,
                      maxLength: 160,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          hintText: 'Tell us about yourself...'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: const TextStyle(color: Colors.pinkAccent)),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                            backgroundColor: VioraColors.mauve),
                        child: _saving
                            ? const CircularProgressIndicator()
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
      );
}
