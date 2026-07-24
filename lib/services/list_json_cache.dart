import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk + memory cache for list API JSON (Sparkle-style instant open).
class ListJsonCache {
  ListJsonCache._();
  static final ListJsonCache instance = ListJsonCache._();

  final Map<String, List<dynamic>> _memory = {};
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/list_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  File _file(String key) => File('${_dir!.path}/${_safeKey(key)}.json');

  static String _safeKey(String key) =>
      key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  List<dynamic>? readMemory(String key) => _memory[key];

  Future<List<dynamic>> load(String key) async {
    final mem = _memory[key];
    if (mem != null && mem.isNotEmpty) return List<dynamic>.from(mem);

    try {
      await _cacheDir();
      final file = _file(key);
      if (!await file.exists()) return const [];
      final text = await file.readAsString();
      if (text.isEmpty) return const [];
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      _memory[key] = decoded;
      return List<dynamic>.from(decoded);
    } catch (e) {
      debugPrint('ListJsonCache.load($key): $e');
      return const [];
    }
  }

  Future<void> save(String key, List<dynamic> data) async {
    if (data.isEmpty) return;
    _memory[key] = List<dynamic>.from(data);
    try {
      await _cacheDir();
      await _file(key).writeAsString(jsonEncode(data), flush: false);
    } catch (e) {
      debugPrint('ListJsonCache.save($key): $e');
    }
  }

  void clearMemory(String key) => _memory.remove(key);
}
