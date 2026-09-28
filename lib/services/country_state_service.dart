import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Free Countries Now API (no key): https://countriesnow.space
///
/// Countries:
///   GET https://countriesnow.space/api/v0.1/countries/iso
/// States for a country:
///   GET https://countriesnow.space/api/v0.1/countries/states/q?country={name}
///   POST https://countriesnow.space/api/v0.1/countries/states
///     body: { "country": "{name}" }
class CountryStateService {
  CountryStateService._();

  static const baseUrl = 'https://countriesnow.space/api/v0.1';
  static const countriesUrl = '$baseUrl/countries/iso';
  static const statesUrl = '$baseUrl/countries/states/q';
  static const statesPostUrl = '$baseUrl/countries/states';

  static List<String>? _countriesCache;
  static final Map<String, List<String>> _statesCache = {};

  static Future<List<String>> fetchCountries() async {
    if (_countriesCache != null && _countriesCache!.isNotEmpty) {
      return List<String>.from(_countriesCache!);
    }
    final response = await http
        .get(Uri.parse(countriesUrl))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Countries API HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Countries API invalid response');
    if (decoded['error'] == true) {
      throw Exception(decoded['msg']?.toString() ?? 'Countries API error');
    }
    final data = decoded['data'];
    if (data is! List) throw Exception('Countries API missing data');
    final names = <String>[];
    for (final row in data) {
      if (row is! Map) continue;
      final name = row['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) names.add(name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _countriesCache = names;
    return List<String>.from(names);
  }

  static Future<List<String>> fetchStates(String country) async {
    final key = country.trim();
    if (key.isEmpty) return const [];
    final cached = _statesCache[key];
    if (cached != null) return List<String>.from(cached);

    final uri = Uri.parse(statesUrl).replace(queryParameters: {'country': key});
    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 25));
    } catch (e) {
      debugPrint('CountryStateService GET states failed, trying POST: $e');
      response = await http
          .post(
            Uri.parse(statesPostUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'country': key}),
          )
          .timeout(const Duration(seconds: 25));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('States API HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('States API invalid response');
    if (decoded['error'] == true) {
      throw Exception(decoded['msg']?.toString() ?? 'States API error');
    }
    final data = decoded['data'];
    List<dynamic>? rawStates;
    if (data is Map) {
      rawStates = data['states'] as List?;
    } else if (data is List) {
      rawStates = data;
    }
    final names = <String>[];
    for (final row in rawStates ?? const []) {
      if (row is Map) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      } else if (row is String && row.trim().isNotEmpty) {
        names.add(row.trim());
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _statesCache[key] = names;
    return List<String>.from(names);
  }
}
