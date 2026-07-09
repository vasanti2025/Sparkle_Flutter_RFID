import 'clients.dart';

class Employee {
  final int id;
  final String? deviceId;
  final int? employeeId;
  final String? clientCode;
  final String? companyNo;
  final int? branchNo;
  final String? compCode;
  final String? branchCode;
  final String? employeeCode;
  final String? firstName;
  final String? lastName;
  final String? empEmail;
  final String? mobileNumber;
  final String? town;
  final String? streetAddress;
  final String? city;
  final String? state;
  final String? country;
  final String? aadharNo;
  final String? panNo;
  final String? dateOfBirth;
  final String? gender;
  final String? designation;
  final String? workLocation;
  final String? department;
  final String? reportingTo;
  final String? bankName;
  final String? accountName;
  final String? bankAccountNo;
  final String? branchName;
  final String? ifscCode;
  final String? joiningDate;
  final String? salary;
  final String? userName;
  final String? password;
  final String? seatingLocation;
  final String? financialYear;
  final String? labelFormat;
  final String? invoiceFormat;
  final String? password2;
  final Clients? clients;
  final String? defaultCompany;
  final int? defaultCompanyId;
  final String? defaultBranch;
  final int defaultBranchId;
  final String? defaultCounter;
  final int? defaultCounterId;
  final String? username;
  final int? roleId;
  final int? userId;

  Employee({
    required this.id,
    this.deviceId,
    this.employeeId,
    this.clientCode,
    this.companyNo,
    this.branchNo,
    this.compCode,
    this.branchCode,
    this.employeeCode,
    this.firstName,
    this.lastName,
    this.empEmail,
    this.mobileNumber,
    this.town,
    this.streetAddress,
    this.city,
    this.state,
    this.country,
    this.aadharNo,
    this.panNo,
    this.dateOfBirth,
    this.gender,
    this.designation,
    this.workLocation,
    this.department,
    this.reportingTo,
    this.bankName,
    this.accountName,
    this.bankAccountNo,
    this.branchName,
    this.ifscCode,
    this.joiningDate,
    this.salary,
    this.userName,
    this.password,
    this.seatingLocation,
    this.financialYear,
    this.labelFormat,
    this.invoiceFormat,
    this.password2,
    this.clients,
    this.defaultCompany,
    this.defaultCompanyId,
    this.defaultBranch,
    required this.defaultBranchId,
    this.defaultCounter,
    this.defaultCounterId,
    this.username,
    this.roleId,
    this.userId,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['Id'] as int? ?? 0,
      deviceId: json['DeviceId'] as String?,
      employeeId: json['EmployeeId'] as int?,
      clientCode: json['ClientCode'] as String?,
      companyNo: json['CompanyNo'] as String?,
      branchNo: json['BranchNo'] as int?,
      compCode: json['CompCode'] as String?,
      branchCode: json['BranchCode'] as String?,
      employeeCode: json['EmployeeCode'] as String?,
      firstName: json['FirstName'] as String?,
      lastName: json['LastName'] as String?,
      empEmail: json['Email'] as String?,
      mobileNumber: json['MobileNumber'] as String?,
      town: json['Town'] as String?,
      streetAddress: json['StreetAddress'] as String?,
      city: json['City'] as String?,
      state: json['State'] as String?,
      country: json['Country'] as String?,
      aadharNo: json['AadharNo'] as String?,
      panNo: json['PanNo'] as String?,
      dateOfBirth: json['DateOfBirth'] as String?,
      gender: json['Gender'] as String?,
      designation: json['Designation'] as String?,
      workLocation: json['WorkLocation'] as String?,
      department: json['Department'] as String?,
      reportingTo: json['ReportingTo'] as String?,
      bankName: json['BankName'] as String?,
      accountName: json['AccountName'] as String?,
      bankAccountNo: json['BankAccountNo'] as String?,
      branchName: json['BranchName'] as String?,
      ifscCode: json['IfscCode'] as String?,
      joiningDate: json['JoiningDate'] as String?,
      salary: json['Salary'] as String?,
      userName: json['UserName'] as String?,
      password: json['Password'] as String?,
      seatingLocation: json['SeatingLocation'] as String?,
      financialYear: json['FinancialYear'] as String?,
      labelFormat: json['LabelFormat'] as String?,
      invoiceFormat: json['InvoiceFormat'] as String?,
      password2: json['Password2'] as String?,
      clients: json['Clients'] != null
          ? Clients.fromJson(json['Clients'] as Map<String, dynamic>)
          : null,
      defaultCompany: json['DefaultCompany'] as String?,
      defaultCompanyId: json['DefaultCompanyId'] as int?,
      defaultBranch: json['DefaultBranch'] as String?,
      defaultBranchId: json['DefaultBranchId'] as int? ?? 1,
      defaultCounter: json['DefaultCounter'] as String?,
      defaultCounterId: json['DefaultCounterId'] as int?,
      username: json['Username'] as String?,
      roleId: json['RoleId'] as int?,
      userId: json['UserId'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'DeviceId': deviceId,
      'EmployeeId': employeeId,
      'ClientCode': clientCode,
      'CompanyNo': companyNo,
      'BranchNo': branchNo,
      'CompCode': compCode,
      'BranchCode': branchCode,
      'EmployeeCode': employeeCode,
      'FirstName': firstName,
      'LastName': lastName,
      'Email': empEmail,
      'MobileNumber': mobileNumber,
      'Town': town,
      'StreetAddress': streetAddress,
      'City': city,
      'State': state,
      'Country': country,
      'AadharNo': aadharNo,
      'PanNo': panNo,
      'DateOfBirth': dateOfBirth,
      'Gender': gender,
      'Designation': designation,
      'WorkLocation': workLocation,
      'Department': department,
      'ReportingTo': reportingTo,
      'BankName': bankName,
      'AccountName': accountName,
      'BankAccountNo': bankAccountNo,
      'BranchName': branchName,
      'IfscCode': ifscCode,
      'JoiningDate': joiningDate,
      'Salary': salary,
      'UserName': userName,
      'Password': password,
      'SeatingLocation': seatingLocation,
      'FinancialYear': financialYear,
      'LabelFormat': labelFormat,
      'InvoiceFormat': invoiceFormat,
      'Password2': password2,
      'Clients': clients?.toJson(),
      'DefaultCompany': defaultCompany,
      'DefaultCompanyId': defaultCompanyId,
      'DefaultBranch': defaultBranch,
      'DefaultBranchId': defaultBranchId,
      'DefaultCounter': defaultCounter,
      'DefaultCounterId': defaultCounterId,
      'Username': username,
      'RoleId': roleId,
      'UserId': userId,
    };
  }
}
