class CustomerModel {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? perAddStreet;
  final String? currAddStreet;
  final String? mobile;
  final String? email;
  final String? password;
  final String? customerLoginId;
  final String? dateOfBirth;
  final String? middleName;
  final String? perAddPincode;
  final String? gender;
  final String? onlineStatus;
  final String? currAddTown;
  final String? currAddPincode;
  final String? currAddState;
  final String? perAddTown;
  final String? perAddState;
  final String? gstNo;
  final String? panNo;
  final String? aadharNo;
  final String? balanceAmount;
  final String? advanceAmount;
  final String? discount;
  final String? creditPeriod;
  final String? fineGold;
  final String? fineSilver;
  final String? clientCode;
  final int? vendorId;
  final bool? addToVendor;
  final int? customerSlabId;
  final int? creditPeriodId;
  final int? rateOfInterestId;
  final String? createdOn;
  final String? lastUpdated;
  final bool? statusType;
  final String? remark;
  final String? area;
  final String? city;
  final String? country;

  CustomerModel({
    this.id,
    this.firstName,
    this.lastName,
    this.perAddStreet,
    this.currAddStreet,
    this.mobile,
    this.email,
    this.password,
    this.customerLoginId,
    this.dateOfBirth,
    this.middleName,
    this.perAddPincode,
    this.gender,
    this.onlineStatus,
    this.currAddTown,
    this.currAddPincode,
    this.currAddState,
    this.perAddTown,
    this.perAddState,
    this.gstNo,
    this.panNo,
    this.aadharNo,
    this.balanceAmount,
    this.advanceAmount,
    this.discount,
    this.creditPeriod,
    this.fineGold,
    this.fineSilver,
    this.clientCode,
    this.vendorId,
    this.addToVendor,
    this.customerSlabId,
    this.creditPeriodId,
    this.rateOfInterestId,
    this.createdOn,
    this.lastUpdated,
    this.statusType,
    this.remark,
    this.area,
    this.city,
    this.country,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    bool? asBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      final s = v.toString().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return null;
    }

    return CustomerModel(
      id: asInt(json['Id']),
      firstName: json['FirstName']?.toString(),
      lastName: json['LastName']?.toString(),
      perAddStreet: json['PerAddStreet']?.toString(),
      currAddStreet: json['CurrAddStreet']?.toString(),
      mobile: json['Mobile']?.toString(),
      email: json['Email']?.toString(),
      password: json['Password']?.toString(),
      customerLoginId: json['CustomerLoginId']?.toString(),
      dateOfBirth: json['DateOfBirth']?.toString(),
      middleName: json['MiddleName']?.toString(),
      perAddPincode: json['PerAddPincode']?.toString(),
      gender: json['Gender']?.toString(),
      onlineStatus: json['OnlineStatus']?.toString(),
      currAddTown: json['CurrAddTown']?.toString(),
      currAddPincode: json['CurrAddPincode']?.toString(),
      currAddState: json['CurrAddState']?.toString(),
      perAddTown: json['PerAddTown']?.toString(),
      perAddState: json['PerAddState']?.toString(),
      gstNo: json['GstNo']?.toString(),
      panNo: json['PanNo']?.toString(),
      aadharNo: json['AadharNo']?.toString(),
      balanceAmount: json['BalanceAmount']?.toString(),
      advanceAmount: json['AdvanceAmount']?.toString(),
      discount: json['Discount']?.toString(),
      creditPeriod: json['CreditPeriod']?.toString(),
      fineGold: json['FineGold']?.toString(),
      fineSilver: json['FineSilver']?.toString(),
      clientCode: json['ClientCode']?.toString(),
      vendorId: asInt(json['VendorId']),
      addToVendor: asBool(json['AddToVendor']),
      customerSlabId: asInt(json['CustomerSlabId']),
      creditPeriodId: asInt(json['CreditPeriodId']),
      rateOfInterestId: asInt(json['RateOfInterestId']),
      createdOn: json['CreatedOn']?.toString(),
      lastUpdated: json['LastUpdated']?.toString(),
      statusType: asBool(json['StatusType']),
      remark: json['Remark']?.toString(),
      area: json['Area']?.toString(),
      city: json['City']?.toString(),
      country: json['Country']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'FirstName': firstName,
      'LastName': lastName,
      'PerAddStreet': perAddStreet,
      'CurrAddStreet': currAddStreet,
      'Mobile': mobile,
      'Email': email,
      'Password': password,
      'CustomerLoginId': customerLoginId,
      'DateOfBirth': dateOfBirth,
      'MiddleName': middleName,
      'PerAddPincode': perAddPincode,
      'Gender': gender,
      'OnlineStatus': onlineStatus,
      'CurrAddTown': currAddTown,
      'CurrAddPincode': currAddPincode,
      'CurrAddState': currAddState,
      'PerAddTown': perAddTown,
      'PerAddState': perAddState,
      'GstNo': gstNo,
      'PanNo': panNo,
      'AadharNo': aadharNo,
      'BalanceAmount': balanceAmount,
      'AdvanceAmount': advanceAmount,
      'Discount': discount,
      'CreditPeriod': creditPeriod,
      'FineGold': fineGold,
      'FineSilver': fineSilver,
      'ClientCode': clientCode,
      'VendorId': vendorId,
      'AddToVendor': addToVendor,
      'CustomerSlabId': customerSlabId,
      'CreditPeriodId': creditPeriodId,
      'RateOfInterestId': rateOfInterestId,
      'CreatedOn': createdOn,
      'LastUpdated': lastUpdated,
      'StatusType': statusType,
      'Remark': remark,
      'Area': area,
      'City': city,
      'Country': country,
    };
  }
}
