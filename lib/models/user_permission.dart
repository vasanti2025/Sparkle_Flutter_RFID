import 'dart:convert';

int _jsonInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _jsonObjectString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

class BranchSelection {
  final int id;
  final String name;

  BranchSelection({required this.id, required this.name});

  factory BranchSelection.fromJson(Map<String, dynamic> json) => BranchSelection(
        id: _jsonInt(json['Id'] ?? json['id'] ?? json['BranchId'] ?? json['branchId']),
        name: (json['Name'] ?? json['name'] ?? json['BranchName'] ?? json['branchName'])
                ?.toString() ??
            '',
      );
}

List<BranchSelection> parseBranchSelectionJson(String? json) {
  if (json == null || json.trim().isEmpty || json.trim() == 'null') return [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    final out = <BranchSelection>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final branch = BranchSelection.fromJson(Map<String, dynamic>.from(e));
      if (branch.name.isNotEmpty || branch.id > 0) out.add(branch);
    }
    return out;
  } catch (_) {
    return [];
  }
}

class UserPermission {
  final int userId;
  final String firstName;
  final String lastName;
  final int roleId;
  final String roleName;
  final String clientCode;
  final String branchSelectionJson;
  final String companySelectionJson;
  final int employeeId;

  UserPermission({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.roleId,
    required this.roleName,
    required this.clientCode,
    required this.branchSelectionJson,
    required this.companySelectionJson,
    required this.employeeId,
  });

  String get displayName {
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    if (name.isNotEmpty) return name;
    return employeeId > 0 ? employeeId.toString() : userId.toString();
  }

  factory UserPermission.fromJson(Map<String, dynamic> json) => UserPermission(
        userId: _jsonInt(json['UserId'] ?? json['userId']),
        firstName: json['FirstName']?.toString() ?? json['firstName']?.toString() ?? '',
        lastName: json['LastName']?.toString() ?? json['lastName']?.toString() ?? '',
        roleId: _jsonInt(json['RoleId'] ?? json['roleId']),
        roleName: json['RoleName']?.toString() ?? json['roleName']?.toString() ?? '',
        clientCode: json['ClientCode']?.toString() ?? json['clientCode']?.toString() ?? '',
        branchSelectionJson: _jsonObjectString(
          json['BranchSelectionJson'] ?? json['branchSelectionJson'],
        ),
        companySelectionJson: _jsonObjectString(
          json['CompanySelectionJson'] ?? json['companySelectionJson'],
        ),
        employeeId: _jsonInt(json['EmployeeId'] ?? json['employeeId']),
      );
}
