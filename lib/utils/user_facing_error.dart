import 'package:dio/dio.dart';

/// Maps only true no-internet / connectivity failures to a short user message.
/// Timeouts, HTTP/server errors, validation, and business errors are unchanged.
/// Does not change API, DB, or offline behavior — display only.
class UserFacingError {
  static const noInternet =
      'No internet connection. Please check your internet connection.';

  static bool isNetwork(Object error) {
    if (error is DioException) {
      // A server response is never a "no internet" failure.
      if (error.response != null) return false;
      // Keep existing timeout messages (login, Order, uploads, etc.).
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return false;
      }
      if (error.type == DioExceptionType.connectionError) return true;
    }

    final text = error.toString().toLowerCase();
    // Never rewrite timeouts or "check internet / try again" business copy.
    if (text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('took longer than')) {
      return false;
    }

    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('host lookup') ||
        text.contains('connection errored') ||
        text.contains('network is unreachable') ||
        text.contains('no address associated') ||
        text.contains('no internet') ||
        text.contains('software caused connection abort') ||
        text.contains('errno = 7') ||
        text.contains('errno = 8') ||
        text.contains('errno = 101');
  }

  static String of(Object error, {String? noInternetMessage}) {
    if (isNetwork(error)) return noInternetMessage ?? noInternet;
    return error.toString();
  }

  static String fromMessage(
    String? message, {
    String? fallback,
    String? noInternetMessage,
  }) {
    if (message == null || message.trim().isEmpty) {
      return fallback ?? '';
    }
    return of(message, noInternetMessage: noInternetMessage);
  }
}
