class LocationItem {
  final int id;
  final String? clientCode;
  final int? userId;
  final int? branchId;
  final String latitude;
  final String longitude;
  final String? address;
  final String? createdOn;
  final String? lastUpdated;
  final bool? statusType;

  LocationItem({
    required this.id,
    this.clientCode,
    this.userId,
    this.branchId,
    required this.latitude,
    required this.longitude,
    this.address,
    this.createdOn,
    this.lastUpdated,
    this.statusType,
  });

  static bool? _parseStatusType(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return null;
  }

  factory LocationItem.fromJson(Map<String, dynamic> json) {
    num? asNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '');
    return LocationItem(
      id: asNum(json['Id'] ?? json['id'])?.toInt() ?? 0,
      clientCode: (json['ClientCode'] ?? json['clientCode'])?.toString(),
      userId: asNum(json['UserId'] ?? json['userId'])?.toInt(),
      branchId: asNum(json['BranchId'] ?? json['branchId'])?.toInt(),
      latitude: (json['Latitude'] ?? json['latitude'])?.toString() ?? '0',
      longitude: (json['Longitude'] ?? json['longitude'])?.toString() ?? '0',
      address: (json['Address'] ?? json['address'])?.toString(),
      createdOn: (json['CreatedOn'] ?? json['createdOn'])?.toString(),
      lastUpdated: (json['LastUpdated'] ?? json['lastUpdated'])?.toString(),
      statusType: _parseStatusType(json['StatusType'] ?? json['statusType']),
    );
  }

  Map<String, dynamic> toMap() => {
        'Id': id,
        'ClientCode': clientCode,
        'UserId': userId,
        'BranchId': branchId,
        'Latitude': latitude,
        'Longitude': longitude,
        'Address': address,
        'CreatedOn': createdOn,
        'LastUpdated': lastUpdated,
        'StatusType': statusType == true ? 1 : 0,
      };

  factory LocationItem.fromMap(Map<String, dynamic> map) {
    return LocationItem(
      id: (map['Id'] as num?)?.toInt() ?? 0,
      clientCode: map['ClientCode']?.toString(),
      userId: (map['UserId'] as num?)?.toInt(),
      branchId: (map['BranchId'] as num?)?.toInt(),
      latitude: map['Latitude']?.toString() ?? '0',
      longitude: map['Longitude']?.toString() ?? '0',
      address: map['Address']?.toString(),
      createdOn: map['CreatedOn']?.toString(),
      lastUpdated: map['LastUpdated']?.toString(),
      statusType: map['StatusType'] == 1,
    );
  }
}
