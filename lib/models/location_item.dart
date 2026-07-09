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

  factory LocationItem.fromJson(Map<String, dynamic> json) {
    return LocationItem(
      id: (json['Id'] as num?)?.toInt() ?? 0,
      clientCode: json['ClientCode']?.toString(),
      userId: (json['UserId'] as num?)?.toInt(),
      branchId: (json['BranchId'] as num?)?.toInt(),
      latitude: json['Latitude']?.toString() ?? '0',
      longitude: json['Longitude']?.toString() ?? '0',
      address: json['Address']?.toString(),
      createdOn: json['CreatedOn']?.toString(),
      lastUpdated: json['LastUpdated']?.toString(),
      statusType: json['StatusType'] as bool?,
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
