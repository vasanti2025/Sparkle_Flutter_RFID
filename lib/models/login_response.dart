import 'employee.dart';

class LoginResponse {
  final Employee? employee;
  final String? token;

  LoginResponse({
    this.employee,
    this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      employee: json['Employee'] != null
          ? Employee.fromJson(json['Employee'] as Map<String, dynamic>)
          : null,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Employee': employee?.toJson(),
      'token': token,
    };
  }
}
