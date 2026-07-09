import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailService {
  /// Sends an email with optional attachments using Hostinger SMTP.
  static Future<bool> sendEmailWithAttachment({
    required List<String> toEmails,
    required String subject,
    required String bodyHtml,
    required Map<String, File> attachments, // filename -> File object
  }) async {
    // Exact Hostinger credentials matched from Kotlin codebase
    final smtpServer = SmtpServer(
      'smtp.hostinger.com',
      username: 'android@loyalstring.com',
      password: 'Android@456#',
      port: 465,
      ssl: true,
    );

    final message = Message()
      ..from = const Address('android@loyalstring.com', 'Sparkle ERP')
      ..recipients.addAll(toEmails)
      ..subject = subject
      ..html = bodyHtml;

    attachments.forEach((filename, file) {
      if (file.existsSync()) {
        message.attachments.add(FileAttachment(file, fileName: filename));
      } else {
        debugPrint('⚠️ Attachment file does not exist: ${file.path}');
      }
    });

    try {
      final sendReport = await send(message, smtpServer);
      debugPrint('✅ SMTP Email sent successfully: $sendReport');
      return true;
    } catch (e) {
      debugPrint('❌ SMTP Email failed to send: $e');
      throw Exception('Email sending failed: $e');
    }
  }
}
