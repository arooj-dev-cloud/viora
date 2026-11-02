import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Saves chat photos and videos (sent or received) into the phone gallery.
/// Voice messages are never saved here.
class GalleryService {
  GalleryService._();

  static const _prefsKey = 'viora_gallery_saved_paths';
  static const _album = 'Viora';
  static final Set<String> _inFlight = <String>{};

  static bool isImage(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.png') ||
        p.endsWith('.webp');
  }

  static bool isVideo(String path) => path.toLowerCase().endsWith('.mp4');

  static bool isVoice(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.m4a') || p.endsWith('.aac') || p.endsWith('.ogg');
  }

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<bool> _wasSaved(String storagePath) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? const <String>[])
        .contains(storagePath);
  }

  static Future<void> _markSaved(String storagePath) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? <String>[];
    if (!list.contains(storagePath)) {
      list.add(storagePath);
      await prefs.setStringList(_prefsKey, list);
    }
  }

  static String? lastError;

  static Future<void> _put(String filePath, String storagePath) async {
    Future<void> attempt() async {
      if (isVideo(storagePath)) {
        await Gal.putVideo(filePath, album: _album);
      } else {
        await Gal.putImage(filePath, album: _album);
      }
    }

    try {
      await attempt();
    } on GalException {
      // Ask for access once, then retry.
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) rethrow;
      await attempt();
    }
    await _markSaved(storagePath);
  }

  /// Saves bytes that are already in memory (used right after sending).
  /// Returns null on success, or an error message.
  static Future<String?> saveSentBytes(
    String storagePath,
    Uint8List bytes,
  ) async {
    if (!_supported || isVoice(storagePath)) return null;
    try {
      final dir = await getTemporaryDirectory();
      final ext = storagePath.split('.').last;
      final file = File(
        '${dir.path}/viora_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _put(file.path, storagePath);
      await file.delete();
      return null;
    } catch (e) {
      lastError = e.toString();
      return e.toString();
    }
  }

  /// Downloads an attachment from private storage and saves it once.
  /// Returns true when the file is in the gallery (new or already saved).
  static Future<bool> saveAttachment(
    String storagePath, {
    bool force = false,
  }) async {
    if (!_supported || isVoice(storagePath)) return false;
    if (!isImage(storagePath) && !isVideo(storagePath)) return false;
    if (!force && await _wasSaved(storagePath)) return true;
    if (!_inFlight.add(storagePath)) return false;
    lastError = null;
    try {
      final bytes = await Supabase.instance.client.storage
          .from('message-attachments')
          .download(storagePath);
      final dir = await getTemporaryDirectory();
      final ext = storagePath.split('.').last;
      final file = File(
        '${dir.path}/viora_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(bytes, flush: true);
      await _put(file.path, storagePath);
      await file.delete();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    } finally {
      _inFlight.remove(storagePath);
    }
  }
}
