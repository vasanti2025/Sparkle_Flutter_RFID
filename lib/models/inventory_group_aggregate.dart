class InventoryGroupAggregate {
  final String name;
  final int totalQty;
  final int matchedQty;
  final double totalGwt;
  final double matchedGwt;

  const InventoryGroupAggregate({
    required this.name,
    required this.totalQty,
    required this.matchedQty,
    required this.totalGwt,
    required this.matchedGwt,
  });

  int get unmatchedQty => totalQty - matchedQty;
  double get unmatchedGwt => totalGwt - matchedGwt;
  bool get fullyMatched => totalQty > 0 && matchedQty >= totalQty;
}
