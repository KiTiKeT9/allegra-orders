import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final String releaseDate;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.releaseDate,
  });
}

class UpdateService {
  static const String _updateUrl = 'https://api.github.com/repos/KiTiKeT9/allegra-orders/releases/latest';
  static const String _releasesPageUrl = 'https://github.com/KiTiKeT9/allegra-orders/releases/latest';
  static const String _lastCheckKey = 'last_update_check';
  static const Duration _checkInterval = Duration(minutes: 30);

  static Future<UpdateInfo?> _fetchLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse(_updateUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('Update check failed: HTTP ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);

      if (data['tag_name'] == null) {
        debugPrint('No tag_name in response');
        return null;
      }

      final version = (data['tag_name'] as String).replaceFirst('v', '');
      final notes = (data['body'] as String?) ?? 'Нет описания';
      final date = (data['published_at'] as String?) ?? '';

      String apkUrl = _releasesPageUrl;
      final assets = data['assets'] as List?;
      if (assets != null) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String;
            break;
          }
        }
      }

      return UpdateInfo(
        version: version,
        downloadUrl: apkUrl,
        releaseNotes: notes,
        releaseDate: date,
      );
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final l = i < latestParts.length ? latestParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _shouldCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      return now - lastCheck > _checkInterval.inMilliseconds;
    } catch (e) {
      return true;
    }
  }

  static Future<void> _saveLastCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {}
  }

  static Future<void> checkForUpdate(BuildContext context, {bool force = false}) async {
    if (!force && !await _shouldCheck()) {
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final release = await _fetchLatestRelease();
    if (release == null) {
      if (force && context.mounted) {
        _showErrorDialog(context, 'Не удалось проверить обновления. Проверьте подключение к интернету.');
      }
      return;
    }

    await _saveLastCheck();

    if (_isNewerVersion(currentVersion, release.version)) {
      if (context.mounted) {
        _showUpdateDialog(context, release);
      }
    } else if (force && context.mounted) {
      _showNoUpdateDialog(context, currentVersion);
    }
  }

  static void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(info: info),
    );
  }

  static void _showNoUpdateDialog(BuildContext context, String version) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            ),
            const SizedBox(width: 12),
            const Text('Обновлений нет', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          'У вас установлена актуальная версия $version',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
            ),
            const SizedBox(width: 12),
            const Text('Ошибка', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openDownload(BuildContext context, String url) async {
    Navigator.pop(context);
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Не удалось открыть ссылку'),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update, color: Color(0xFF6366F1)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Доступно обновление', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Новая версия: ${info.version}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0F19),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Позже', style: TextStyle(color: Color(0xFF64748B))),
        ),
        ElevatedButton.icon(
          onPressed: () => UpdateService._openDownload(context, info.downloadUrl),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Обновить'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }
}
