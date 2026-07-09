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
    return Clients(
      clientCode: json['ClientCode'] as String?,
      rdPurchaseFormat: json['RDPurchaseFormat'] as String?,
      firstName: json['FirstName'] as String?,
      lastName: json['LastName'] as String?,
      mobile: json['Mobile'] as String?,
      clientEmail: json['ClientEmail'] as String?,
      userName: json['UserName'] as String?,
      password: json['Password'] as String?,
      websiteAddress: json['WebsiteAddress'] as String?,
      streetAddress: json['StreetAddress'] as String?,
      town: json['Town'] as String?,
      city: json['City'] as String?,
      state: json['State'] as String?,
      country: json['Country'] as String?,
      postalCode: json['PostalCode'] as String?,
      panNo: json['PanNo'] as String?,
      gstNo: json['GSTNo'] as String?,
      aadharNo: json['AadharNo'] as String?,
      plan: json['Plan'] as String?,
      ecommerceUrl: json['EcommerceUrl'] as String?,
      emailForOtp: json['EmailForOTP'] as String?,
      baseCurrency: json['BaseCurrency'] as String?,
      profilePic: json['ProfilePic'] as String?,
      clientType: json['ClientType'] as String?,
      organisationName: json['OrganisationName'] as String?,
      organisationDetails: json['OrganisationDetails'] as String?,
      advertisementPointBalance: json['AdvertisementPointBalance'] as String?,
      balanceAmt: json['BalanceAmt'] as String?,
      fineSilver: json['FineSilver'] as String?,
      fineGold: json['FineGold'] as String?,
      advanceAmt: json['AdvanceAmt'] as String?,
      planStartDate: json['PlanStartDate'] as String?,
      planExpiryDate: json['PlanExpiryDate'] as String?,
      paymentStatus: json['PaymentStatus'] as String?,
      labelFormat: json['LabelFormat'] as String?,
      invoiceFormat: json['InvoiceFormat'] as String?,
      rfidType: json['RfidType'] as String?,
      id: json['Id'] as int? ?? 0,
      createdOn: json['CreatedOn'] as String?,
      lastUpdated: json['LastUpdated'] as String?,
      statusType: json['StatusType'] as bool? ?? false,
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
