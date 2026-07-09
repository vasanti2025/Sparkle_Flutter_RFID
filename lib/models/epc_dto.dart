class EpcDto {
  final int? id;
  final String barcodeNumber;
  final String tidValue;
  final String clientCode;
  final String createdOn;
  final String lastUpdated;
  final bool statusType;

  EpcDto({
    this.id,
    required this.barcodeNumber,
    required this.tidValue,
    required this.clientCode,
    required this.createdOn,
    required this.lastUpdated,
    required this.statusType,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'BarcodeNumber': barcodeNumber,
      'TidValue': tidValue,
      'ClientCode': clientCode,
      'CreatedOn': createdOn,
      'LastUpdated': lastUpdated,
      'StatusType': statusType ? 1 : 0,
    };
  }

  factory EpcDto.fromMap(Map<String, dynamic> map) {
    return EpcDto(
      id: map['id'] as int?,
      barcodeNumber: map['BarcodeNumber'] as String? ?? '',
      tidValue: map['TidValue'] as String? ?? '',
      clientCode: map['ClientCode'] as String? ?? '',
      createdOn: map['CreatedOn'] as String? ?? '',
      lastUpdated: map['LastUpdated'] as String? ?? '',
      statusType: (map['StatusType'] as int? ?? 0) == 1,
    );
  }

  factory EpcDto.fromJson(Map<String, dynamic> json) {
    return EpcDto(
      id: json['Id'] as int?,
      barcodeNumber: json['BarcodeNumber'] as String? ?? '',
      tidValue: json['TidValue'] as String? ?? '',
      clientCode: json['ClientCode'] as String? ?? '',
      createdOn: json['CreatedOn'] as String? ?? '',
      lastUpdated: json['LastUpdated'] as String? ?? '',
      statusType: json['StatusType'] as bool? ?? false,
    );
  }
}
