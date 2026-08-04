import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Debug-only logging for API calls, failures, and crashes.
class AppLogger {
  AppLogger._();

  static const String _tag = 'SparkleRFID';
  static const int _maxBodyChars = 6000;

  static bool get enabled => kDebugMode;

  /// Bootstraps Flutter and runs [runApp] in the same zone (debug crash zone optional).
  static void bootstrapAndRunApp(Widget app) {
    void startApp() {
      WidgetsFlutterBinding.ensureInitialized();
      if (enabled) installCrashHandlers();
      runApp(app);
    }

    if (!enabled) {
      startApp();
      return;
    }

    runZonedGuarded(
      startApp,
      (Object error, StackTrace stack) {
        logCrash(source: 'UncaughtZone', error: error, stackTrace: stack);
      },
    );
  }

  static void installCrashHandlers() {
    if (!enabled) return;

    final prevFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      logCrash(
        source: 'FlutterError',
        error: details.exception,
        stackTrace: details.stack,
        context: details.context?.toString(),
        library: details.library,
      );
      if (prevFlutterHandler != null) {
        prevFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final prevPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logCrash(source: 'PlatformDispatcher', error: error, stackTrace: stack);
      return prevPlatformHandler?.call(error, stack) ?? true;
    };
  }

  static void log(String message, {String? tag}) {
    if (!enabled) return;
    final name = tag ?? _tag;
    developer.log(message, name: name);
    debugPrint('[$name] $message');
  }

  static void logCrash({
    required String source,
    required Object error,
    StackTrace? stackTrace,
    String? context,
    String? library,
  }) {
    if (!enabled) return;

    final buffer = StringBuffer('CRASH [$source] $error');
    if (library != null && library.isNotEmpty) {
      buffer.write(' | library=$library');
    }
    if (context != null && context.isNotEmpty) {
      buffer.write(' | context=$context');
    }
    log(buffer.toString(), tag: 'CRASH');
    if (stackTrace != null) {
      log(stackTrace.toString(), tag: 'CRASH');
    }
  }

  static void logApiRequest({
    required String method,
    required String url,
    Map<String, dynamic>? headers,
    Object? body,
  }) {
    if (!enabled) return;
    log('→ $method $url', tag: 'API');
    final safeHeaders = _sanitizeMap(headers);
    if (safeHeaders.isNotEmpty) {
      log('  headers: ${_encode(safeHeaders)}', tag: 'API');
    }
    if (body != null) {
      log('  body: ${_truncate(_encode(_sanitizeBody(body)))}', tag: 'API');
    }
  }

  static void logApiResponse({
    required String method,
    required String url,
    required int? statusCode,
    required Duration elapsed,
    Object? data,
  }) {
    if (!enabled) return;
    log(
      '← ${statusCode ?? '-'} $method $url (${elapsed.inMilliseconds}ms)',
      tag: 'API',
    );
    if (data != null) {
      log('  response: ${_truncate(_encode(_sanitizeBody(data)))}', tag: 'API');
    }
  }

  static void logApiFailure({
    required String method,
    required String url,
    required Duration elapsed,
    required Object error,
    int? statusCode,
    Object? responseData,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    log(
      '✗ FAILED ${statusCode ?? '-'} $method $url (${elapsed.inMilliseconds}ms)',
      tag: 'API',
    );
    log('  error: $error', tag: 'API');
    if (responseData != null) {
      log(
        '  error-response: ${_truncate(_encode(_sanitizeBody(responseData)))}',
        tag: 'API',
      );
    }
    if (stackTrace != null) {
      log('  stack: $stackTrace', tag: 'API');
    }
  }

  static Object? _sanitizeBody(Object? value) {
    if (value is Map) {
      return _sanitizeMap(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is List) {
      return value.map(_sanitizeBody).toList();
    }
    if (value is FormData) {
      return {
        'fields': value.fields,
        'files': value.files.map((f) => f.key).toList(),
      };
    }
    return value;
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic>? input) {
    if (input == null || input.isEmpty) return {};
    const sensitiveKeys = {
      'password',
      'Password',
      'confirmPassword',
      'ConfirmPassword',
      'token',
      'Token',
      'authorization',
      'Authorization',
    };
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (sensitiveKeys.contains(key)) {
        out[key] = '***';
      } else if (value is Map) {
        out[key] = _sanitizeMap(Map<String, dynamic>.from(value));
      } else if (value is List) {
        out[key] = value.map(_sanitizeBody).toList();
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  static String _encode(Object? value) {
    if (value == null) return 'null';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  static String _truncate(String text) {
    if (text.length <= _maxBodyChars) return text;
    return '${text.substring(0, _maxBodyChars)}... [truncated ${text.length - _maxBodyChars} chars]';
  }
}
