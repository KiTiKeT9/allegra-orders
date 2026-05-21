import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderService extends ChangeNotifier {
  String _serverUrl = 'http://192.168.1.1:8000';
  bool _isUploading = false;
  String? _lastError;

  String get serverUrl => _serverUrl;
  bool get isUploading => _isUploading;
  String? get lastError => _lastError;

  OrderService() {
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null && saved.isNotEmpty) {
      _serverUrl = saved;
      notifyListeners();
    }
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    notifyListeners();
  }

  Future<bool> checkConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/health'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> checkOrderExists(String orderNumber) async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/check-order/$orderNumber'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'exists': data['exists'] ?? false,
          'windowsCount': data['windows_count'] ?? 0,
        };
      }
      return {'exists': false, 'windowsCount': 0};
    } catch (e) {
      return {'exists': false, 'windowsCount': 0};
    }
  }

  Future<bool> uploadOrder(
    String orderNumber,
    List<XFile> files, {
    int count = 1,
    int windowNumber = 1,
    bool appendMode = false,
    Function(double progress, int sent, int total)? onProgress,
  }) async {
    if (orderNumber.isEmpty || files.isEmpty) {
      _lastError = 'Номер заказа или файлы отсутствуют';
      return false;
    }
    _isUploading = true;
    _lastError = null;
    notifyListeners();

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 900);
      dio.options.sendTimeout = const Duration(seconds: 900);

      final formData = FormData();
      formData.fields.add(MapEntry('order_number', orderNumber));
      formData.fields.add(MapEntry('count', count.toString()));
      formData.fields.add(MapEntry('window_number', windowNumber.toString()));
      formData.fields.add(MapEntry('append_mode', appendMode.toString()));

      for (var file in files) {
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(file.path, filename: file.name),
        ));
      }

      final response = await dio.post(
        '$_serverUrl/api/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) {
            onProgress(sent / total, sent, total);
          }
        },
      );

      _isUploading = false;
      notifyListeners();

      if (response.statusCode == 200) {
        return true;
      } else {
        _lastError = 'Ошибка сервера: ${response.statusCode}';
        return false;
      }
    } catch (e) {
      _isUploading = false;
      _lastError = 'Ошибка сети: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> getDiskInfo() async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/disk-info'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'total': 0, 'free': 0, 'used': 0, 'percentUsed': 0};
    } catch (e) {
      return {'total': 0, 'free': 0, 'used': 0, 'percentUsed': 0, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getOrderFiles(String orderNumber) async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/api/files/$orderNumber'),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['files'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  String downloadUrl(String orderNumber, String filePath) {
    return '$_serverUrl/api/download/$orderNumber/$filePath';
  }

  Future<String?> downloadFile(String orderNumber, String filePath, {Function(double)? onProgress}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/downloads');
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      final fileName = filePath.split('/').last;
      final savePath = '${saveDir.path}/$fileName';

      final dio = Dio();
      await dio.download(
        downloadUrl(orderNumber, filePath),
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      return savePath;
    } catch (e) {
      _lastError = 'Download error: $e';
      return null;
    }
  }
}
