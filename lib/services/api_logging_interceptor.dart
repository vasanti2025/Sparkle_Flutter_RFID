import 'package:dio/dio.dart';

import '../utils/app_logger.dart';

/// Logs every Dio request, response, and failure.
class ApiLoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (AppLogger.enabled) {
      try {
        options.extra['_api_started_at'] = DateTime.now();
        AppLogger.logApiRequest(
          method: options.method,
          url: _fullUrl(options),
          headers: Map<String, dynamic>.from(options.headers),
          body: _logBody(options.path, options.extra, options.data),
        );
      } catch (e) {
        AppLogger.log('API request log failed: $e', tag: 'API');
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (AppLogger.enabled) {
      try {
        AppLogger.logApiResponse(
          method: response.requestOptions.method,
          url: _fullUrl(response.requestOptions),
          statusCode: response.statusCode,
          elapsed: _elapsed(response.requestOptions),
          data: _logBody(
            response.requestOptions.path,
            response.requestOptions.extra,
            response.data,
          ),
        );
      } catch (e) {
        AppLogger.log('API response log failed: $e', tag: 'API');
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (AppLogger.enabled) {
      try {
        AppLogger.logApiFailure(
          method: err.requestOptions.method,
          url: _fullUrl(err.requestOptions),
          elapsed: _elapsed(err.requestOptions),
          error: err.message ?? err.type,
          statusCode: err.response?.statusCode,
          responseData: _logBody(
            err.requestOptions.path,
            err.requestOptions.extra,
            err.response?.data,
          ),
          stackTrace: err.stackTrace,
        );
      } catch (e) {
        AppLogger.log('API error log failed: $e', tag: 'API');
      }
    }
    handler.next(err);
  }

  Object? _logBody(String path, Map<String, dynamic> extra, Object? data) {
    if (extra['skip_api_log_body'] == true ||
        path.toLowerCase().contains('getallstockverificationbysession')) {
      if (data == null) return null;
      if (data is String) return '[omitted ${data.length} chars]';
      if (data is List) return '[omitted list ${data.length}]';
      if (data is Map) return '[omitted map keys=${data.keys.length}]';
      return '[omitted ${data.runtimeType}]';
    }
    return data;
  }

  String _fullUrl(RequestOptions options) {
    if (options.uri.toString().isNotEmpty) return options.uri.toString();
    final base = options.baseUrl;
    final path = options.path;
    if (base.endsWith('/') && path.startsWith('/')) {
      return '$base${path.substring(1)}';
    }
    if (!base.endsWith('/') && !path.startsWith('/')) {
      return '$base/$path';
    }
    return '$base$path';
  }

  Duration _elapsed(RequestOptions options) {
    final started = options.extra['_api_started_at'];
    if (started is DateTime) {
      return DateTime.now().difference(started);
    }
    return Duration.zero;
  }
}
