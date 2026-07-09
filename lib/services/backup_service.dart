import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'email_service.dart';

class BackupService {
  static Future<String> dbPath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'sparkle_rfid.db');
  }

  static Future<File> saveToDevice() async {
    final source = File(await dbPath());
    if (!await source.exists()) throw Exception('Database not found');

    final backupDir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'backup'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);

    final dest = File(p.join(backupDir.path, 'sparkle_rfid_backup.db'));
    await source.copy(dest.path);
    return dest;
  }

  static Future<void> sendViaEmail(String recipientEmail) async {
    final source = File(await dbPath());
    if (!await source.exists()) throw Exception('Database not found');

    final tempDir = await getTemporaryDirectory();
    final dbCopy = File(p.join(tempDir.path, 'sparkle_rfid_backup.db'));
    await source.copy(dbCopy.path);

    await EmailService.sendEmailWithAttachment(
      toEmails: [recipientEmail],
      subject: 'SparkleERP Backup',
      bodyHtml: "Here's your latest backup file.",
      attachments: {'sparkle_rfid_backup.db': dbCopy},
    );
  }

  static Future<File?> pickRestoreFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null) return null;
    return File(path);
  }

  static Future<void> restoreFromFile(File backupFile) async {
    final targetPath = await dbPath();
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
      final wal = File('$targetPath-wal');
      final shm = File('$targetPath-shm');
      if (await wal.exists()) await wal.delete();
      if (await shm.exists()) await shm.delete();
    }
    await backupFile.copy(targetPath);
  }
}
