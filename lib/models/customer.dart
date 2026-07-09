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
    return CustomerModel(
      id: json['Id'] as int?,
      firstName: json['FirstName'] as String?,
      lastName: json['LastName'] as String?,
      perAddStreet: json['PerAddStreet'] as String?,
      currAddStreet: json['CurrAddStreet'] as String?,
      mobile: json['Mobile'] as String?,
      email: json['Email'] as String?,
      password: json['Password'] as String?,
      customerLoginId: json['CustomerLoginId'] as String?,
      dateOfBirth: json['DateOfBirth'] as String?,
      middleName: json['MiddleName'] as String?,
      perAddPincode: json['PerAddPincode'] as String?,
      gender: json['Gender'] as String?,
      onlineStatus: json['OnlineStatus'] as String?,
      currAddTown: json['CurrAddTown'] as String?,
      currAddPincode: json['CurrAddPincode'] as String?,
      currAddState: json['CurrAddState'] as String?,
      perAddTown: json['PerAddTown'] as String?,
      perAddState: json['PerAddState'] as String?,
      gstNo: json['GstNo'] as String?,
      panNo: json['PanNo'] as String?,
      aadharNo: json['AadharNo'] as String?,
      balanceAmount: json['BalanceAmount']?.toString(),
      advanceAmount: json['AdvanceAmount']?.toString(),
      discount: json['Discount']?.toString(),
      creditPeriod: json['CreditPeriod']?.toString(),
      fineGold: json['FineGold']?.toString(),
      fineSilver: json['FineSilver']?.toString(),
      clientCode: json['ClientCode'] as String?,
      vendorId: json['VendorId'] as int?,
      addToVendor: json['AddToVendor'] as bool?,
      customerSlabId: json['CustomerSlabId'] as int?,
      creditPeriodId: json['CreditPeriodId'] as int?,
      rateOfInterestId: json['RateOfInterestId'] as int?,
      createdOn: json['CreatedOn'] as String?,
      lastUpdated: json['LastUpdated'] as String?,
      statusType: json['StatusType'] as bool?,
      remark: json['Remark'] as String?,
      area: json['Area'] as String?,
      city: json['City'] as String?,
      country: json['Country'] as String?,
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
