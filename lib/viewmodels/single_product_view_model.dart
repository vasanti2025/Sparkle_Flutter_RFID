import 'package:flutter/foundation.dart';
import '../models/product_master.dart';
import '../services/api_service.dart';
import '../services/pref_service.dart';

class SingleProductViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final ApiService _apiService;

  SingleProductViewModel({
    required PrefService prefService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _apiService = apiService;

  bool _loading = false;
  bool _saving = false;
  String? _message;
  String? _error;

  List<VendorModel> _vendors = [];
  List<SkuModel> _skus = [];
  List<CategoryModel> _categories = [];
  List<ProductMasterModel> _products = [];
  List<DesignModel> _designs = [];
  List<PurityModel> _purities = [];

  bool get loading => _loading;
  bool get saving => _saving;
  String? get message => _message;
  String? get error => _error;

  String get clientCode => _prefService.getEmployee()?.clientCode ?? '';
  int get branchId => _prefService.getEmployee()?.defaultBranchId ?? 1;
  int get employeeCode => _prefService.getEmployee()?.employeeId ?? 0;

  List<VendorModel> get vendors => _vendors;
  List<SkuModel> get skus => _skus;
  List<CategoryModel> get categories => _categories;
  List<ProductMasterModel> get products => _products;
  List<DesignModel> get designs => _designs;
  List<PurityModel> get purities => _purities;

  Future<void> loadMasterData() async {
    if (clientCode.isEmpty) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _apiService.getAllVendors(clientCode),
        _apiService.getAllSku(clientCode),
        _apiService.getAllCategories(clientCode),
        _apiService.getAllProductMaster(clientCode),
        _apiService.getAllDesigns(clientCode),
        _apiService.getAllPurity(clientCode),
      ]);

      _vendors = (results[0] as List).map((e) => VendorModel.fromJson(e as Map<String, dynamic>)).toList();
      _skus = (results[1] as List).map((e) => SkuModel.fromJson(e as Map<String, dynamic>)).toList();
      _categories = (results[2] as List).map((e) => CategoryModel.fromJson(e as Map<String, dynamic>)).toList();
      _products = (results[3] as List).map((e) => ProductMasterModel.fromJson(e as Map<String, dynamic>)).toList();
      _designs = (results[4] as List).map((e) => DesignModel.fromJson(e as Map<String, dynamic>)).toList();
      _purities = (results[5] as List).map((e) => PurityModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<SkuModel> skusForVendor(String vendorName) {
    if (vendorName.isEmpty) return _skus;
    final needle = vendorName.trim().toLowerCase();
    return _skus.where((s) {
      if ((s.vendorName ?? '').trim().toLowerCase() == needle) return true;
      return s.vendorNames.any((v) => v.trim().toLowerCase() == needle);
    }).toList();
  }

  List<ProductMasterModel> productsForCategory(int categoryId) {
    if (categoryId == 0) return _products;
    return _products.where((p) => p.categoryId == categoryId).toList();
  }

  List<DesignModel> designsForProduct(int productId) {
    if (productId == 0) return _designs;
    return _designs.where((d) => d.productId == productId).toList();
  }

  List<PurityModel> puritiesForCategory(int categoryId) {
    if (categoryId == 0) return _purities;
    return _purities.where((p) => p.categoryId == categoryId).toList();
  }

  CategoryModel? categoryByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final c in _categories) {
      if (c.name.trim().toLowerCase() == needle) return c;
    }
    return null;
  }

  ProductMasterModel? productByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final p in _products) {
      if (p.name.trim().toLowerCase() == needle) return p;
    }
    return null;
  }

  DesignModel? designByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final d in _designs) {
      if (d.name.trim().toLowerCase() == needle) return d;
    }
    return null;
  }

  PurityModel? purityByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final p in _purities) {
      if (p.name.trim().toLowerCase() == needle) return p;
    }
    return null;
  }

  VendorModel? vendorByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final v in _vendors) {
      if (v.name.trim().toLowerCase() == needle) return v;
    }
    return null;
  }

  SkuModel? skuByName(String name, {String? vendorName}) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final pool = vendorName != null && vendorName.trim().isNotEmpty
        ? skusForVendor(vendorName)
        : _skus;
    for (final s in pool) {
      if (s.sku.trim().toLowerCase() == needle) return s;
    }
    return null;
  }

  static String calculateNetWeight(String gross, String stone, String diamond) {
    final g = double.tryParse(gross) ?? 0;
    final s = double.tryParse(stone) ?? 0;
    final d = double.tryParse(diamond) ?? 0;
    final net = g - s - (d * 0.200);
    if (net <= 0) return '';
    return net.toStringAsFixed(3);
  }

  Future<bool> saveProduct({
    required int categoryId,
    required int productId,
    required int designId,
    required int vendorId,
    required int purityId,
    required String rfidCode,
    required String epc,
    required String grossWt,
    required String stoneWt,
    required String netWt,
    required String diamondWt,
    required String makingPerc,
    required String makingGm,
    required String fixMaking,
    required String fixWastage,
    required String stoneAmt,
    required String diamondAmt,
    SkuModel? sku,
  }) async {
    _saving = true;
    _message = null;
    _error = null;
    notifyListeners();

    try {
      final payload = buildInsertProductPayload(
        categoryId: categoryId,
        productId: productId,
        designId: designId,
        vendorId: vendorId,
        purityId: purityId,
        rfidCode: rfidCode,
        epc: epc,
        grossWt: grossWt,
        stoneWt: stoneWt,
        netWt: netWt,
        diamondWt: diamondWt,
        makingPerc: makingPerc,
        makingGm: makingGm,
        fixMaking: fixMaking,
        fixWastage: fixWastage,
        stoneAmt: stoneAmt,
        diamondAmt: diamondAmt,
        branchId: sku?.branchId != null && sku!.branchId != 0 ? sku.branchId : branchId,
        clientCode: sku?.clientCode.isNotEmpty == true ? sku!.clientCode : clientCode,
        employeeCode: sku?.employeeId != null && sku!.employeeId != 0 ? sku.employeeId : employeeCode,
      );

      final msg = await _apiService.insertLabelledStock(payload);
      _message = msg ?? 'Product saved successfully';
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  void clearMessages() {
    _message = null;
    _error = null;
    notifyListeners();
  }
}
