import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/login_request.dart';
import '../models/login_response.dart';
import '../models/location_item.dart';
import '../models/stock_transfer_models.dart';
import '../models/user_permission.dart';
import 'pref_service.dart';

class ApiService {
  static const String defaultBaseUrl = 'https://rrgold.loyalstring.co.in/';
  
  final PrefService _prefService;
  final Dio _dio;

  String get baseUrl {
    String url = _prefService.getCustomApi()?.trim() ?? '';
    if (url.isEmpty) {
      url = defaultBaseUrl;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    return url;
  }

  ApiService(this._prefService) : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(minutes: 5);
    _dio.options.sendTimeout = const Duration(minutes: 5);
    
    // Add interceptor to dynamically rewrite the base URL for every request
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        String baseUrl = _prefService.getCustomApi()?.trim() ?? '';
        if (baseUrl.isEmpty) {
          baseUrl = defaultBaseUrl;
        }
        
        // Ensure base URL starts with http/https
        if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
          baseUrl = 'http://$baseUrl';
        }
        
        // Ensure base URL ends with trailing slash
        if (!baseUrl.endsWith('/')) {
          baseUrl = '$baseUrl/';
        }

        options.baseUrl = baseUrl;
        
        // Add auth token if available
        final token = _prefService.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        
        return handler.next(options);
      },
    ));
  }

  Future<LoginResponse> login(LoginRequest request) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/ClientOnboardingLogin',
        data: request.toJson(),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return LoginResponse.fromJson(data);
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Server returned status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      String errMsg = 'Network error occurred';
      if (e.response != null && e.response?.data != null) {
        // Try parsing error message from response
        final data = e.response?.data;
        if (data is Map && data.containsKey('message')) {
          errMsg = data['message'].toString();
        } else if (data is String && data.isNotEmpty) {
          errMsg = data;
        } else {
          errMsg = 'Error status: ${e.response?.statusCode}';
        }
      } else {
        errMsg = e.message ?? 'Unknown network error';
      }
      throw Exception(errMsg);
    }
  }

  // Delete product API call
  Future<bool> deleteProduct(int id, String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/DeleteLabeledStock',
        data: [
          {'Id': id, 'ClientCode': clientCode}
        ],
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw Exception('Delete API failed: ${e.message}');
    }
  }

  // Update product metadata API call
  Future<bool> updateProduct(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/UpdateLabeledStock',
        data: [payload],
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw Exception('Update API failed: ${e.message}');
    }
  }

  // Upload product image file API call
  Future<String?> uploadProductImage(String clientCode, String itemCode, String filePath) async {
    try {
      final formData = FormData.fromMap({
        'ClientCode': clientCode,
        'ItemCode': itemCode,
        'File': await MultipartFile.fromFile(filePath, filename: filePath.split(RegExp(r'[/\\]')).last),
      });

      final response = await _dio.post(
        'api/ProductMaster/UploadImagesByClientCode ',
        data: formData,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        // Check for both lowercase and capitalized keys to support diverse server serializations
        if (data is Map<String, dynamic>) {
          if (data.containsKey('images')) {
            return data['images'] as String?;
          } else if (data.containsKey('Images')) {
            return data['Images'] as String?;
          }
        } else if (data is String) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              if (decoded.containsKey('images')) {
                return decoded['images'] as String?;
              } else if (decoded.containsKey('Images')) {
                return decoded['Images'] as String?;
              }
            }
          } catch (_) {}
        }
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Image upload failed: ${e.message}');
    }
  }

  // Upload stock verification payload
  Future<bool> uploadStockVerification(String clientCode, List<Map<String, dynamic>> items) async {
    try {
      final payload = {
        'ClientCode': clientCode,
        'Items': items,
      };
      final response = await _dio.post(
        'api/ProductMaster/AddStockVerificationBySession',
        data: payload,
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      final errMsg = e.response?.data?.toString() ?? e.message ?? 'Unknown error';
      throw Exception('Upload failed: $errMsg');
    }
  }

  // Search orders by RFID/Itemcode
  Future<List<dynamic>> searchOrdersByRfid(String clientCode, String query) async {
    try {
      final payload = {
        'ClientCode': clientCode,
        'RfidCode': query,
        'CustomOrderId': int.tryParse(query) ?? 0,
        'OrderId': null,
        'OrderNo': query
      };
      final response = await _dio.post(
        'api/Order/GetAllOrders',
        data: payload,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data;
        }
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Order search failed: ${e.message}');
    }
  }

  // Search boxes by RFID/Itemcode
  Future<Map<String, dynamic>?> getBoxDetailsByRfidCode(String clientCode, String query) async {
    try {
      final payload = {
        'clientCode': clientCode,
        'rfidCode': query
      };
      final response = await _dio.post(
        'api/BoxRfid/GetDetailsByRfidCode',
        data: payload,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Box details search failed: ${e.message}');
    }
  }

  // Get all customers (EmployeeList)
  Future<List<dynamic>> getAllCustomers(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/GetAllCustomer',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load customers: ${e.message}');
    }
  }

  // Add customer
  Future<Map<String, dynamic>?> addCustomer(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/AddCustomer',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to add customer: ${e.message}');
    }
  }

  // Get daily rates
  Future<List<dynamic>> getDailyRates(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllDailyRate',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load daily rates: ${e.message}');
    }
  }

  // Get all purity master (drives the Today's Rate table rows)
  Future<List<dynamic>> getAllPurity(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllPurity',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load purity list: ${e.message}');
    }
  }

  // Update daily rates. Body is a JSON array, one object per purity row.
  Future<bool> updateDailyRates(List<Map<String, dynamic>> rates) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/UpdateDailyRates',
        data: rates,
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw Exception('Failed to update daily rates: ${e.message}');
    }
  }

  // Get last order number
  Future<Map<String, dynamic>?> getLastOrderNo(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/Order/LastOrderNo',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to fetch last order number: ${e.message}');
    }
  }

  // Save/Create customer order
  Future<Map<String, dynamic>?> addCustomOrder(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Order/AddCustomOrder',
        data: request,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        if (data is bool && data) return {'success': true};
        if (data is num) return {'CustomOrderId': data.toInt()};
        if (data is String && data.trim().isNotEmpty) {
          return {'message': data, 'success': true};
        }
        throw Exception('AddCustomOrder unexpected response: $data');
      }
      throw Exception('AddCustomOrder failed: HTTP ${response.statusCode}');
    } on DioException catch (e) {
      final body = e.response?.data;
      throw Exception('Failed to save order: ${e.message} | $body');
    }
  }

  // Update customer order
  Future<Map<String, dynamic>?> updateCustomOrder(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Order/UpdateCustomOrder',
        data: request,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        if (data is bool && data) return {'success': true};
        if (data is String && data.trim().isNotEmpty) {
          return {'message': data, 'success': true};
        }
        throw Exception('UpdateCustomOrder unexpected response: $data');
      }
      throw Exception('UpdateCustomOrder failed: HTTP ${response.statusCode}');
    } on DioException catch (e) {
      final body = e.response?.data;
      throw Exception('Failed to update order: ${e.message} | $body');
    }
  }

  // Delete customer order
  Future<bool> deleteCustomOrder(String clientCode, int customOrderId) async {
    try {
      final response = await _dio.post(
        'api/Order/DeleteCustomOrder',
        data: {
          'clientCode': clientCode,
          'CustomOrderId': customOrderId,
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      throw Exception('Failed to delete order: ${e.message}');
    }
  }


  // Get branches list
  Future<List<dynamic>> getAllBranches(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/GetAllBranchMaster',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load branches: ${e.message}');
    }
  }

  // Get all delivery challans
  Future<List<dynamic>> getAllDeliveryChallans(String clientCode, int branchId) async {
    try {
      final response = await _dio.post(
        'api/Invoice/GetAllDeliveryChallan',
        data: {
          'ClientCode': clientCode,
          'BranchId': branchId,
        },
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load delivery challans: ${e.message}');
    }
  }

  // Get last challan number
  Future<Map<String, dynamic>?> getLastChallanNo(String clientCode, int branchId) async {
    try {
      final response = await _dio.post(
        'api/Invoice/GetLastChallanNo',
        data: {
          'ClientCode': clientCode,
          'BranchId': branchId,
        },
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to fetch last challan number: ${e.message}');
    }
  }

  // Add delivery challan
  Future<Map<String, dynamic>?> addDeliveryChallan(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Invoice/AddDeliveryChallan',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to save delivery challan: ${e.message}');
    }
  }

  // Update delivery challan
  Future<Map<String, dynamic>?> updateDeliveryChallan(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Invoice/UpdateDeliveryChallan',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to update delivery challan: ${e.message}');
    }
  }

  // ---- Quotation APIs (reuse the Order controller endpoints) -------------

  // Get all quotations
  Future<List<dynamic>> getAllQuotations(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/Order/GetAllQuotation',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load quotations: ${e.message}');
    }
  }

  // Get last quotation number
  Future<Map<String, dynamic>?> getLastQuotationNo(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/Order/LastQuotationNo',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to fetch last quotation number: ${e.message}');
    }
  }

  // Save/Create quotation
  Future<Map<String, dynamic>?> addQuotation(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Order/AddQuotation',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to save quotation: ${e.message}');
    }
  }

  // Update quotation (note: server endpoint path is intentionally "Upadate")
  Future<Map<String, dynamic>?> updateQuotation(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Order/UpadateQuotation',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to update quotation: ${e.message}');
    }
  }

  // ---- Sample Out APIs ----------------------------------------------------

  Future<List<dynamic>> getAllSampleOut(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/Transaction/GetAllCustomerIssue',
        data: {
          'ClientCode': clientCode,
          'SampleStatus': 'SampleOut',
        },
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load sample out list: ${e.message}');
    }
  }

  Future<String?> getLastSampleOutNo(String clientCode, int branchId) async {
    try {
      final response = await _dio.post(
        'api/Transaction/GetCustLastSampleOutNo',
        data: {
          'ClientCode': clientCode,
          'BranchId': branchId,
        },
      );
      if (response.statusCode == 200) {
        if (response.data is String) return response.data as String;
        return response.data?.toString();
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to fetch last sample out number: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> addSampleOut(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Transaction/AddCustomerIssue',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to save sample out: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> updateSampleOut(Map<String, dynamic> request) async {
    try {
      final response = await _dio.post(
        'api/Transaction/UpdateCustomerIssue',
        data: request,
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to update sample out: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllSampleIn(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/Transaction/GetAllIssueItemDetails',
        data: {
          'ClientCode': clientCode,
          'SampleStatus': 'SampleIn',
        },
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load sample in list: ${e.message}');
    }
  }

  // Get all customer tunch settings
  Future<List<dynamic>> getAllCustomerTunch(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/Invoice/GetAllCustomerTounch',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return response.data as List;
      }
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load customer tunch: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> getConsolidatedStockVerificationReport({
    required String clientCode,
    required String reportDate,
  }) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetConsolidationStockVerificationReport',
        data: {
          'ClientCode': clientCode,
          'ReportDate': reportDate,
        },
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to load consolidated report: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> getAllStockVerificationSessions(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllStockVerificationBySession',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to load batch sessions: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> getStockVerificationBatchDetails({
    required String clientCode,
    required String scanBatchId,
  }) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllStockVerificationBySession',
        data: {
          'ClientCode': clientCode,
          'ScanBatchId': scanBatchId,
          'ReturnAllData': true,
        },
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw Exception('Failed to load batch details: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllVendors(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllPartyDetails',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) return response.data as List;
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load vendors: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllSku(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllSKU',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) return response.data as List;
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load SKU: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllCategories(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllCategory',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) return response.data as List;
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load categories: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllProductMaster(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllProductMaster',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) return response.data as List;
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load products: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllDesigns(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllDesign',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) return response.data as List;
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load designs: ${e.message}');
    }
  }

  Future<List<dynamic>> getAllRfidTags(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllRFID',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) return response.data as List;
      return [];
    } on DioException catch (e) {
      throw Exception('Failed to load RFID tags: ${e.message}');
    }
  }

  Future<String?> insertLabelledStock(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/InsertLabelledStock',
        data: [payload],
      );
      if (response.statusCode == 200) {
        if (response.data is List && (response.data as List).isNotEmpty) {
          final first = (response.data as List).first;
          if (first is Map && first['Message'] != null) return first['Message'].toString();
        }
        return 'Product saved successfully';
      }
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['Message'] != null) throw Exception(data['Message'].toString());
      throw Exception('Failed to save product: ${e.message}');
    }
  }

  Future<bool> addClientLocation({
    required String clientCode,
    required int userId,
    required int branchId,
    required String latitude,
    required String longitude,
    required String address,
  }) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/AddClientLocation',
        data: {
          'ClientCode': clientCode,
          'UserId': userId,
          'BranchId': branchId,
          'Latitude': latitude,
          'Longitude': longitude,
          'Address': address,
        },
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  Future<List<LocationItem>> getClientLocations({
    required String clientCode,
    required int userId,
    required int branchId,
  }) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/GetClientLocations',
        data: {
          'ClientCode': clientCode,
          'UserId': userId,
          'BranchId': branchId,
        },
      );
      if (response.statusCode != 200) return [];
      final data = response.data;
      if (data is List) {
        return data.map((e) => LocationItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } on DioException {
      return [];
    }
  }

  Future<Map<String, dynamic>?> saveFace(Map<String, dynamic> faceInfo) async {
    try {
      final response = await _dio.post(
        'api/FaceLogin/AddFace',
        data: faceInfo,
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>?;
      }
      throw Exception('Save face failed (HTTP ${response.statusCode})');
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['Message'] != null) {
        throw Exception(body['Message'].toString());
      }
      if (body is Map && body['message'] != null) {
        throw Exception(body['message'].toString());
      }
      throw Exception(e.message ?? 'Failed to save face to server');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }

  Future<Map<String, dynamic>?> getAllFaceLogin(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/FaceLogin/GetAllFaceLogin',
        data: {'clientCode': clientCode},
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>?;
      }
      throw Exception('GetAllFaceLogin failed (HTTP ${response.statusCode})');
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['Message'] != null) {
        throw Exception(body['Message'].toString());
      }
      if (body is Map && body['message'] != null) {
        throw Exception(body['message'].toString());
      }
      throw Exception(e.message ?? 'Failed to load face login data');
    }
  }

  Future<Map<String, dynamic>?> getAllScantoDesktop(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/RFIDDevice/GetAllRFIDDetails',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('Error in getAllScantoDesktop: $e');
      return null;
    }
  }

  Future<bool> addRFIDScannedData(List<Map<String, dynamic>> items) async {
    try {
      final response = await _dio.post(
        'api/RFIDDevice/AddRFID',
        data: items,
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error in addRFIDScannedData: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> clearStockData(String clientCode, String deviceId) async {
    try {
      final response = await _dio.post(
        'api/RFIDDevice/DeleteRFIDByClientAndDevice',
        data: {
          'ClientCode': clientCode,
          'DeviceId': deviceId,
        },
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('Error in clearStockData: $e');
      return null;
    }
  }

  Future<bool> addDeviceId(String clientCode, String deviceId) async {
    try {
      final response = await _dio.post(
        'api/ClientOnboarding/UpdateMultipleUser',
        data: [
          {
            'id': clientCode,
            'deviceId': deviceId,
          }
        ],
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error in addDeviceId: $e');
      return false;
    }
  }

  Future<List<TransferType>> getStockTransferTypes(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetStockTransferTypes',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .whereType<Map<String, dynamic>>()
            .map(TransferType.fromJson)
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getStockTransferTypes: $e');
      return [];
    }
  }

  Future<bool> addStockTransfer(StockTransferRequest request) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/AddStockTransfer',
        data: request.toJson(),
      );
      if (response.statusCode != 200) return false;
      final data = response.data;
      if (data is Map && data['success'] == false) return false;
      return true;
    } catch (e) {
      debugPrint('Error addStockTransfer: $e');
      return false;
    }
  }

  Future<List<StockTransferInOutItem>> getAllStockTransfers(StockInOutRequest request) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/GetAllStockTransfers',
        data: request.toJson(),
      );
      if (response.statusCode == 200) {
        final dynamic body = response.data;
        List<dynamic>? rawList;
        if (body is List) {
          rawList = body;
        } else if (body is Map) {
          for (final key in ['data', 'Data', 'result', 'Result']) {
            if (body[key] is List) {
              rawList = body[key] as List;
              break;
            }
          }
        }
        if (rawList != null) {
          return rawList
              .whereType<Map<String, dynamic>>()
              .map(StockTransferInOutItem.fromJson)
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getAllStockTransfers: $e');
      return [];
    }
  }

  Future<String?> cancelStockTransfer(CancelStockTransferRequest request) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/CancelStockTransferMasterDetails',
        data: request.toJson(),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['Message']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Error cancelStockTransfer: $e');
      return null;
    }
  }

  Future<String?> approveStockTransfer(StApproveRejectRequest request) async {
    try {
      final response = await _dio.post(
        'api/ProductMaster/ApproveStockTransfer',
        data: request.toJson(),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['Message']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Error approveStockTransfer: $e');
      return null;
    }
  }

  Future<List<UserPermission>> getAllUserPermissionsAll(String clientCode) async {
    try {
      final response = await _dio.post(
        'api/RoleManagement/GetAllUserPermissions-Optimized',
        data: {'ClientCode': clientCode},
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .whereType<Map<String, dynamic>>()
            .map(UserPermission.fromJson)
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getAllUserPermissionsAll: $e');
      return [];
    }
  }
}
