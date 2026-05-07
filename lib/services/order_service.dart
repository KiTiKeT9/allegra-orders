import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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

  /// Returns {exists: bool, windowsCount: int}
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
  }) async {
    if (orderNumber.isEmpty || files.isEmpty) {
      _lastError = 'Номер заказа или файлы отсутствуют';
      return false;
    }
    _isUploading = true;
    _lastError = null;
    notifyListeners();

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_serverUrl/api/upload'));
      request.fields['order_number'] = orderNumber;
      request.fields['count'] = count.toString();
      request.fields['window_number'] = windowNumber.toString();
      request.fields['append_mode'] = appendMode.toString();

      for (var file in files) {
        request.files.add(await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: file.name,
        ));
      }

      var streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      var response = await http.Response.fromStream(streamedResponse);

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
}
