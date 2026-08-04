import 'package:dio/dio.dart';

import '../utils/app_logger.dart';

/// Logs every Dio request, response, and failure.
class ApiLoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (AppLogger.enabled) {
      options.extra['_api_started_at'] = DateTime.now();
      AppLogger.logApiRequest(
        method: options.method,
        url: _fullUrl(options),
        headers: Map<String, dynamic>.from(options.headers),
        body: options.data,
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (AppLogger.enabled) {
      AppLogger.logApiResponse(
        method: response.requestOptions.method,
        url: _fullUrl(response.requestOptions),
        statusCode: response.statusCode,
        elapsed: _elapsed(response.requestOptions),
        data: response.data,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (AppLogger.enabled) {
      AppLogger.logApiFailure(
        method: err.requestOptions.method,
        url: _fullUrl(err.requestOptions),
        elapsed: _elapsed(err.requestOptions),
        error: err.message ?? err.type,
        statusCode: err.response?.statusCode,
        responseData: err.response?.data,
        stackTrace: err.stackTrace,
      );
    }
    handler.next(err);
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
