import 'dart:convert';

class BranchSelection {
  final int id;
  final String name;

  BranchSelection({required this.id, required this.name});

  factory BranchSelection.fromJson(Map<String, dynamic> json) => BranchSelection(
        id: (json['Id'] as num?)?.toInt() ?? 0,
        name: json['Name']?.toString() ?? '',
      );
}

List<BranchSelection> parseBranchSelectionJson(String? json) {
  if (json == null || json.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(BranchSelection.fromJson)
        .where((b) => b.name.isNotEmpty)
        .toList();
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
    final name = firstName.trim();
    if (name.isNotEmpty) return '$name ($employeeId)';
    return employeeId.toString();
  }

  factory UserPermission.fromJson(Map<String, dynamic> json) => UserPermission(
        userId: (json['UserId'] as num?)?.toInt() ?? 0,
        firstName: json['FirstName']?.toString() ?? '',
        lastName: json['LastName']?.toString() ?? '',
        roleId: (json['RoleId'] as num?)?.toInt() ?? 0,
        roleName: json['RoleName']?.toString() ?? '',
        clientCode: json['ClientCode']?.toString() ?? '',
        branchSelectionJson: json['BranchSelectionJson']?.toString() ?? '',
        companySelectionJson: json['CompanySelectionJson']?.toString() ?? '',
        employeeId: (json['EmployeeId'] as num?)?.toInt() ?? 0,
      );
}
