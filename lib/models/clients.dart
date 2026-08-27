class Clients {
  final String? clientCode;
  final String? rdPurchaseFormat;
  final String? firstName;
  final String? lastName;
  final String? mobile;
  final String? clientEmail;
  final String? userName;
  final String? password;
  final String? websiteAddress;
  final String? streetAddress;
  final String? town;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final String? panNo;
  final String? gstNo;
  final String? aadharNo;
  final String? plan;
  final String? ecommerceUrl;
  final String? emailForOtp;
  final String? baseCurrency;
  final String? profilePic;
  final String? clientType;
  final String? organisationName;
  final String? organisationDetails;
  final String? advertisementPointBalance;
  final String? balanceAmt;
  final String? fineSilver;
  final String? fineGold;
  final String? advanceAmt;
  final String? planStartDate;
  final String? planExpiryDate;
  final String? paymentStatus;
  final String? labelFormat;
  final String? invoiceFormat;
  final String? rfidType;
  final int id;
  final String? createdOn;
  final String? lastUpdated;
  final bool statusType;

  Clients({
    this.clientCode,
    this.rdPurchaseFormat,
    this.firstName,
    this.lastName,
    this.mobile,
    this.clientEmail,
    this.userName,
    this.password,
    this.websiteAddress,
    this.streetAddress,
    this.town,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.panNo,
    this.gstNo,
    this.aadharNo,
    this.plan,
    this.ecommerceUrl,
    this.emailForOtp,
    this.baseCurrency,
    this.profilePic,
    this.clientType,
    this.organisationName,
    this.organisationDetails,
    this.advertisementPointBalance,
    this.balanceAmt,
    this.fineSilver,
    this.fineGold,
    this.advanceAmt,
    this.planStartDate,
    this.planExpiryDate,
    this.paymentStatus,
    this.labelFormat,
    this.invoiceFormat,
    this.rfidType,
    required this.id,
    this.createdOn,
    this.lastUpdated,
    required this.statusType,
  });

  factory Clients.fromJson(Map<String, dynamic> json) {
    String? str(dynamic value) {
      if (value == null) return null;
      final s = value.toString();
      return s == 'null' ? null : s;
    }

    return Clients(
      clientCode: str(json['ClientCode']),
      rdPurchaseFormat: str(json['RDPurchaseFormat']),
      firstName: str(json['FirstName']),
      lastName: str(json['LastName']),
      mobile: str(json['Mobile']),
      clientEmail: str(json['ClientEmail']),
      userName: str(json['UserName']),
      password: str(json['Password']),
      websiteAddress: str(json['WebsiteAddress']),
      streetAddress: str(json['StreetAddress']),
      town: str(json['Town']),
      city: str(json['City']),
      state: str(json['State']),
      country: str(json['Country']),
      postalCode: str(json['PostalCode']),
      panNo: str(json['PanNo']),
      gstNo: str(json['GSTNo']),
      aadharNo: str(json['AadharNo']),
      plan: str(json['Plan']),
      ecommerceUrl: str(json['EcommerceUrl']),
      emailForOtp: str(json['EmailForOTP']),
      baseCurrency: str(json['BaseCurrency']),
      profilePic: str(json['ProfilePic']),
      clientType: str(json['ClientType']),
      organisationName: str(json['OrganisationName']),
      organisationDetails: str(json['OrganisationDetails']),
      advertisementPointBalance: str(json['AdvertisementPointBalance']),
      balanceAmt: str(json['BalanceAmt']),
      fineSilver: str(json['FineSilver']),
      fineGold: str(json['FineGold']),
      advanceAmt: str(json['AdvanceAmt']),
      planStartDate: str(json['PlanStartDate']),
      planExpiryDate: str(json['PlanExpiryDate']),
      paymentStatus: str(json['PaymentStatus']),
      labelFormat: str(json['LabelFormat']),
      invoiceFormat: str(json['InvoiceFormat']),
      rfidType: str(json['RfidType'] ?? json['rfidType']),
      id: (json['Id'] as num?)?.toInt() ?? int.tryParse('${json['Id'] ?? ''}') ?? 0,
      createdOn: str(json['CreatedOn']),
      lastUpdated: str(json['LastUpdated']),
      statusType: json['StatusType'] == true || json['StatusType'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ClientCode': clientCode,
      'RDPurchaseFormat': rdPurchaseFormat,
      'FirstName': firstName,
      'LastName': lastName,
      'Mobile': mobile,
      'ClientEmail': clientEmail,
      'UserName': userName,
      'Password': password,
      'WebsiteAddress': websiteAddress,
      'StreetAddress': streetAddress,
      'Town': town,
      'City': city,
      'State': state,
      'Country': country,
      'PostalCode': postalCode,
      'PanNo': panNo,
      'GSTNo': gstNo,
      'AadharNo': aadharNo,
      'Plan': plan,
      'EcommerceUrl': ecommerceUrl,
      'EmailForOTP': emailForOtp,
      'BaseCurrency': baseCurrency,
      'ProfilePic': profilePic,
      'ClientType': clientType,
      'OrganisationName': organisationName,
      'OrganisationDetails': organisationDetails,
      'AdvertisementPointBalance': advertisementPointBalance,
      'BalanceAmt': balanceAmt,
      'FineSilver': fineSilver,
      'FineGold': fineGold,
      'AdvanceAmt': advanceAmt,
      'PlanStartDate': planStartDate,
      'PlanExpiryDate': planExpiryDate,
      'PaymentStatus': paymentStatus,
      'LabelFormat': labelFormat,
      'InvoiceFormat': invoiceFormat,
      'RfidType': rfidType,
      'Id': id,
      'CreatedOn': createdOn,
      'LastUpdated': lastUpdated,
      'StatusType': statusType,
    };
  }
}
