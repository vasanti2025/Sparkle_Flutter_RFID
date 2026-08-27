class WholesaleBranch {
  final int id;
  final String name;

  const WholesaleBranch({required this.id, required this.name});

  factory WholesaleBranch.fromJson(Map<String, dynamic> json) {
    return WholesaleBranch(
      id: readWholesaleInt(json, const ['Id', 'id', 'BranchId', 'branchId']),
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
    return WholesaleCounter(
      id: readWholesaleInt(json, const ['Id', 'id', 'CounterId', 'counterId']),
      name: readWholesaleString(json, const ['CounterName', 'counterName', 'Name', 'name']),
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

  Map<String, dynamic> toApiJson() {
    if (branchId <= 0 || counterId <= 0) return <String, dynamic>{};
    return {
      'BranchId': branchId,
      'BranchName': branchName,
      'CounterId': counterId,
      'CounterName': counterName,
      'CounterNumber': counterName.trim().isNotEmpty ? counterName.trim() : '$counterId',
    };
  }

  Map<String, dynamic> toPrefJson() => {
        'BranchId': branchId,
        'BranchName': branchName,
        'CounterId': counterId,
        'CounterName': counterName,
      };
}

/// Swagger: each assignment is one branch + one counter (ints, not arrays).
List<Map<String, dynamic>> wholesaleAssignmentsToApi(List<RfidDeviceAssignment> assignments) {
  return assignments.map((a) => a.toApiJson()).where((m) => m.isNotEmpty).toList();
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
    return RfidDeviceInfo(
      id: readWholesaleInt(json, const ['Id', 'id', 'DeviceId', 'RFIDDeviceId']),
      deviceId: readWholesaleString(json, const ['DeviceId', 'deviceId']),
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
  List<dynamic>? list;
  if (data is List) {
    list = data;
  } else if (data is Map) {
    for (final key in [
      'Assignments',
      'assignments',
      'data',
      'Data',
      'result',
      'Result',
      'RFIDDeviceAssignments',
    ]) {
      if (data[key] is List) {
        list = data[key] as List;
        break;
      }
    }
    if (list == null && (data['BranchId'] != null || data['branchId'] != null || data['BranchName'] != null)) {
      list = [data];
    }
  }
  if (list == null) return [];
  return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
