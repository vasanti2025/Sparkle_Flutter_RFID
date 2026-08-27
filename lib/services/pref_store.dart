import 'package:shared_preferences/shared_preferences.dart';

/// Minimal backing store for [PrefService] — memory for instant boot, disk after upgrade.
abstract class PrefStore {
  String? getString(String key);
  bool? getBool(String key);
  int? getInt(String key);
  bool containsKey(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setBool(String key, bool value);
  Future<bool> setInt(String key, int value);
  Future<bool> remove(String key);
  Future<bool> clear();
}

class SharedPrefStore implements PrefStore {
  SharedPrefStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  bool containsKey(String key) => _prefs.containsKey(key);

  @override
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> clear() => _prefs.clear();
}

class MemoryPrefStore implements PrefStore {
  MemoryPrefStore([Map<String, Object?>? seed]) : _data = {...?seed};

  final Map<String, Object?> _data;

  Map<String, Object?> exportAll() => Map<String, Object?>.from(_data);

  void put(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  void applySnapshot(Map<String, dynamic> snapshot) {
    snapshot.forEach((key, value) {
      if (value == null) return;
      put(key, value);
    });
  }

  /// Loads persisted prefs over bootstrap seed — disk is source of truth on cold start.
  void importFromSharedPreferences(SharedPreferences prefs) {
    for (final key in prefs.getKeys()) {
      try {
        final val = prefs.get(key);
        if (val != null) {
          put(key, val);
        }
      } catch (e) {
        print('Error importing preference key $key: $e');
      }
    }
  }

  @override
  String? getString(String key) {
    final v = _data[key];
    return v is String ? v : v?.toString();
  }

  @override
  bool? getBool(String key) {
    final v = _data[key];
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == 'true';
    return null;
  }

  @override
  int? getInt(String key) {
    final v = _data[key];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  Future<void> mergeInto(SharedPreferences prefs) async {
    for (final entry in _data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value != null) {
        await prefs.setString(key, value.toString());
      }
    }
  }

  /// Like [mergeInto], but never overwrite durable session keys with empty values.
  Future<void> mergeSessionSafeInto(SharedPreferences prefs) async {
    const protectEmpty = {
      'token',
      'employee',
      'client',
      'session_username',
      'session_password',
    };
    for (final entry in _data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        if (protectEmpty.contains(key) &&
            value.isEmpty &&
            (prefs.getString(key)?.isNotEmpty ?? false)) {
          continue;
        }
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value != null) {
        await prefs.setString(key, value.toString());
      }
    }
  }
}
