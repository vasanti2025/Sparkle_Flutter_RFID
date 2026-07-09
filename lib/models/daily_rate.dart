/// A single editable "Today's Rate" row, combining a purity master entry with
/// its current daily rate. Mirrors the Kotlin `DailyRateResponse` row model.
class DailyRate {
  final int categoryId;
  final String categoryName;
  final String clientCode;
  final String employeeCode;
  final String finePercentage;
  final int purityId;
  final String purityName;

  /// Editable rate per gram (kept as a string so the text field can show
  /// exactly what the user / server provides, e.g. "6500.00").
  String rate;

  DailyRate({
    required this.categoryId,
    required this.categoryName,
    required this.clientCode,
    required this.employeeCode,
    required this.finePercentage,
    required this.purityId,
    required this.purityName,
    required this.rate,
  });

  /// JSON object sent in the UpdateDailyRates request array.
  Map<String, dynamic> toUpdateJson() {
    return {
      'CategoryId': categoryId,
      'CategoryName': categoryName,
      'ClientCode': clientCode,
      'EmployeeCode': employeeCode,
      'FinePercentage': finePercentage,
      'PurityId': purityId,
      'PurityName': purityName,
      'Rate': rate,
    };
  }
}
