/// Platform block from `GetAppVersionConfig` / `SaveAppVersionConfig`.
class AppVersionInfo {
  const AppVersionInfo({
    this.currentVersion = '',
    this.minimumSupportedVersion = '',
    this.latestVersion = '',
    this.forceUpdate = true,
    this.storeUrl,
  });

  final String currentVersion;
  final String minimumSupportedVersion;
  final String latestVersion;
  final bool forceUpdate;
  final String? storeUrl;

  /// Version the installed app must match (`currentVersion`, else latest).
  String get expectedVersion {
    if (currentVersion.trim().isNotEmpty) return currentVersion.trim();
    if (latestVersion.trim().isNotEmpty) return latestVersion.trim();
    return minimumSupportedVersion.trim();
  }

  bool get hasVersion => expectedVersion.isNotEmpty;

  /// Parses `{ status, data: { android: {...}, ios: {...} } }`.
  static AppVersionInfo? fromConfigResponse(dynamic data, {required bool ios}) {
    if (data is! Map) return null;
    final root = Map<String, dynamic>.from(data);
    dynamic payload = root['data'] ?? root['Data'] ?? root;
    if (payload is! Map) return null;
    final map = Map<String, dynamic>.from(payload);
    final block = ios
        ? (map['ios'] ?? map['iOS'] ?? map['Ios'] ?? map['IOS'])
        : (map['android'] ?? map['Android']);
    return fromPlatformBlock(block);
  }

  static AppVersionInfo? fromPlatformBlock(dynamic block) {
    if (block is! Map) return null;
    final map = Map<String, dynamic>.from(block);
    final current = _readString(map, const ['currentVersion', 'CurrentVersion']);
    final min = _readString(map, const [
      'minimumSupportedVersion',
      'MinimumSupportedVersion',
    ]);
    final latest = _readString(map, const ['latestVersion', 'LatestVersion']);
    if ((current == null || current.isEmpty) &&
        (latest == null || latest.isEmpty) &&
        (min == null || min.isEmpty)) {
      return null;
    }
    return AppVersionInfo(
      currentVersion: current ?? '',
      minimumSupportedVersion: min ?? '',
      latestVersion: latest ?? '',
      forceUpdate: _readBool(map, const [
            'forceUpdate',
            'ForceUpdate',
            'isForceUpdate',
            'IsForceUpdate',
          ]) ??
          true,
      storeUrl: _readString(map, const [
        'storeUrl',
        'StoreUrl',
        'playStoreUrl',
        'PlayStoreUrl',
        'appUrl',
        'AppUrl',
      ]),
    );
  }

  Map<String, dynamic> toPlatformJson() => {
        'currentVersion': currentVersion,
        'minimumSupportedVersion': minimumSupportedVersion,
        'latestVersion': latestVersion,
        'forceUpdate': forceUpdate,
        if (storeUrl != null && storeUrl!.trim().isNotEmpty) 'storeUrl': storeUrl,
      };

  static String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool? _readBool(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key];
      if (raw is bool) return raw;
      final text = raw?.toString().trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
    }
    return null;
  }
}
