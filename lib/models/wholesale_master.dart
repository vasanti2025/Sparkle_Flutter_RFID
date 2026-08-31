class WholesaleBranch {
  final int id;
  final String name;

  const WholesaleBranch({required this.id, required this.name});

  factory WholesaleBranch.fromJson(Map<String, dynamic> json) {
    // Prefer BranchId so it matches GetAllCounters.BranchId (e.g. 1 → Counter1/2/3).
    return WholesaleBranch(
      id: readWholesaleInt(json, const ['BranchId', 'branchId', 'Id', 'id']),
      name: readWholesaleString(json, const ['BranchName', 'branchName', 'Name', 'name']),
    );
  }
}

class WholesaleCounter {
  final int id;
  final String name;
  final int branchId;

  const WholesaleCounter({
    required this.id,
    required this.name,
    required this.branchId,
  });

  factory WholesaleCounter.fromJson(Map<String, dynamic> json) {
    // GetAllCounters: Id=5, BranchId=1, CounterName/CounterNumber="Counter1"
    final name = readWholesaleString(json, const [
      'CounterName',
      'counterName',
      'CounterNumber',
      'counterNumber',
      'Name',
      'name',
    ]);
    return WholesaleCounter(
      id: readWholesaleInt(json, const ['Id', 'id', 'CounterId', 'counterId']),
      name: name,
      branchId: readWholesaleInt(json, const ['BranchId', 'branchId']),
    );
  }
}

class RfidDeviceAssignment {
  final int branchId;
  final String branchName;
  final int counterId;
  final String counterName;

  const RfidDeviceAssignment({
    this.branchId = 0,
    this.branchName = '',
    this.counterId = 0,
    this.counterName = '',
  });

  bool get hasBranch => branchId > 0 || branchName.trim().isNotEmpty;
  bool get hasCounter => counterId > 0 || counterName.trim().isNotEmpty;
  bool get isValid => hasBranch && hasCounter;

  factory RfidDeviceAssignment.fromJson(Map<String, dynamic> json) {
    return RfidDeviceAssignment(
      branchId: readWholesaleInt(json, const ['BranchId', 'branchId']),
      branchName: readWholesaleString(json, const ['BranchName', 'branchName']),
      counterId: readWholesaleInt(json, const ['CounterId', 'counterId']),
      counterName: readWholesaleString(json, const ['CounterName', 'counterName']),
    );
  }

  Map<String, dynamic> toPrefJson() => {
        'BranchId': branchId,
        'BranchName': branchName,
        'CounterId': counterId,
        'CounterName': counterName,
      };
}

/// Assign API shape (Swagger) — one object per branch, CounterId always an array:
///   { "BranchId": 1, "CounterId": [3, 4, 5] }
List<Map<String, dynamic>> wholesaleAssignmentsToApi(List<RfidDeviceAssignment> assignments) {
  final byBranch = <int, List<int>>{};
  for (final a in assignments) {
    if (a.branchId <= 0 || a.counterId <= 0) {
      // ignore: avoid_print
      print(
        'wholesaleAssignmentsToApi DROP row branchId=${a.branchId} '
        'counterId=${a.counterId} name=${a.counterName}',
      );
      continue;
    }
    final list = byBranch.putIfAbsent(a.branchId, () => <int>[]);
    if (!list.contains(a.counterId)) list.add(a.counterId);
  }
  if (byBranch.isEmpty) {
    // ignore: avoid_print
    print('wholesaleAssignmentsToApi => empty (no BranchId/CounterId pairs)');
    return const [];
  }

  final out = <Map<String, dynamic>>[];
  for (final entry in byBranch.entries) {
    final counterIds = List<int>.from(entry.value)..sort();
    out.add({
      'BranchId': entry.key,
      'CounterId': counterIds,
    });
    // ignore: avoid_print
    print(
      'wholesaleAssignmentsToApi branch=${entry.key} '
      'counters=$counterIds (count=${counterIds.length})',
    );
  }
  return out;
}

class RfidDeviceInfo {
  final int id;
  final String deviceId;
  final String deviceCode;
  final String deviceName;
  final List<RfidDeviceAssignment> assignments;

  const RfidDeviceInfo({
    this.id = 0,
    this.deviceId = '',
    this.deviceCode = '',
    this.deviceName = '',
    this.assignments = const [],
  });

  Object get apiDeviceId => id > 0 ? id : (int.tryParse(deviceId) ?? (deviceId.isNotEmpty ? deviceId : deviceCode));

  factory RfidDeviceInfo.fromJson(Map<String, dynamic> json) {
    // Prefer table Id; only treat DeviceId as numeric Id when it parses as int
    // (hex DeviceCode strings must not become Id = 0 / wrong value).
    final tableId = readWholesaleInt(json, const ['Id', 'id', 'RFIDDeviceId']);
    final deviceIdRaw = readWholesaleString(json, const ['DeviceId', 'deviceId']);
    final deviceIdAsInt = int.tryParse(deviceIdRaw) ?? 0;
    return RfidDeviceInfo(
      id: tableId > 0 ? tableId : deviceIdAsInt,
      deviceId: deviceIdRaw,
      deviceCode: readWholesaleString(json, const ['DeviceCode', 'deviceCode']),
      deviceName: readWholesaleString(json, const ['DeviceName', 'deviceName', 'Name']),
      assignments: parseWholesaleAssignments(json),
    );
  }
}

int readWholesaleInt(Map<String, dynamic> json, List<String> keys) {
  final ids = readWholesaleIntList(json, keys);
  return ids.isEmpty ? 0 : ids.first;
}

List<int> readWholesaleIntList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final ids = <int>[];
    void add(dynamic item) {
      if (item is int) {
        if (item > 0 && !ids.contains(item)) ids.add(item);
      } else if (item is num) {
        final n = item.toInt();
        if (n > 0 && !ids.contains(n)) ids.add(n);
      } else {
        final parsed = int.tryParse(item.toString().trim());
        if (parsed != null && parsed > 0 && !ids.contains(parsed)) ids.add(parsed);
      }
    }

    if (value is List) {
      for (final item in value) {
        add(item);
      }
    } else {
      add(value);
    }
    if (ids.isNotEmpty) return ids;
  }
  return const [];
}

String readWholesaleString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}

List<Map<String, dynamic>> extractAssignmentMaps(dynamic data) {
  final out = <Map<String, dynamic>>[];

  void walk(dynamic node) {
    if (node is List) {
      for (final item in node) {
        walk(item);
      }
      return;
    }
    if (node is! Map) return;
    final map = Map<String, dynamic>.from(node);

    var nestedAssignments = false;
    for (final key in const [
      'Assignments',
      'assignments',
      'RFIDDeviceAssignments',
    ]) {
      if (map[key] is List) {
        nestedAssignments = true;
        walk(map[key]);
      }
    }
    if (nestedAssignments) return;

    for (final key in const [
      'data',
      'Data',
      'result',
      'Result',
      'Devices',
      'devices',
      'RFIDDevices',
      'rfidDevices',
    ]) {
      if (map[key] is List) {
        walk(map[key]);
        return;
      }
    }

    if (map['BranchId'] != null ||
        map['branchId'] != null ||
        map['BranchName'] != null ||
        map['branchName'] != null ||
        map['CounterId'] != null ||
        map['counterId'] != null ||
        map['CounterName'] != null) {
      out.add(map);
    }
  }

  walk(data);
  return out;
}

List<RfidDeviceAssignment> parseWholesaleAssignments(dynamic data) {
  final out = <RfidDeviceAssignment>[];
  for (final json in extractAssignmentMaps(data)) {
    final branchIds = readWholesaleIntList(json, const ['BranchId', 'branchId']);
    final counterIds = readWholesaleIntList(json, const ['CounterId', 'counterId']);
    final branchName = readWholesaleString(json, const ['BranchName', 'branchName']);
    final counterName = readWholesaleString(json, const ['CounterName', 'counterName']);
    final branches = branchIds.isEmpty ? const [0] : branchIds;
    final counters = counterIds.isEmpty ? const [0] : counterIds;
    for (final branchId in branches) {
      for (final counterId in counters) {
        out.add(
          RfidDeviceAssignment(
            branchId: branchId,
            branchName: branchName,
            counterId: counterId,
            counterName: counterName,
          ),
        );
      }
    }
  }
  return out.where((a) => a.isValid).toList();
}
