import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/order_service.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isChecking = false;
  bool? _connectionStatus;

  @override
  void initState() {
    super.initState();
    final service = Provider.of<OrderService>(context, listen: false);
    _urlController = TextEditingController(text: service.serverUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() { _isChecking = true; _connectionStatus = null; });
    final service = Provider.of<OrderService>(context, listen: false);
    await service.setServerUrl(_urlController.text.trim());
    final ok = await service.checkConnection();
    setState(() { _isChecking = false; _connectionStatus = ok; });
    _showSnack(ok ? 'Подключение успешно!' : 'Не удалось подключиться', isError: !ok);
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF161B2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x1AFFFFFF)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('Настройки', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Server URL
                  _SectionTitle(icon: Icons.dns_outlined, title: 'Сервер'),
                  const SizedBox(height: 12),
                  const Text('Адрес сервера', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFF1F5F9)),
                    decoration: InputDecoration(
                      hintText: 'http://192.168.1.1:8000',
                      suffixIcon: _connectionStatus != null
                          ? Icon(_connectionStatus! ? Icons.check_circle : Icons.error,
                              color: _connectionStatus! ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : _testConnection,
                      child: _isChecking
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Проверить и сохранить'),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Update
                  _SectionTitle(icon: Icons.system_update, title: 'Обновление'),
                  const SizedBox(height: 12),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.hasData ? snapshot.data!.version : '...';
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF6366F1), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Текущая версия: $version',
                                      style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => UpdateService.checkForUpdate(context, force: true),
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Проверить обновления'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF6366F1),
                                        side: const BorderSide(color: Color(0xFF6366F1)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Help
                  _SectionTitle(icon: Icons.info_outline, title: 'Как подключиться'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('1. Убедитесь, что ПК и телефон в одной Wi-Fi сети.', style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.6)),
                        Text('2. На ПК откройте вкладку "Сервер" и посмотрите IP-адрес.', style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.6)),
                        Text('3. Введите адрес в формате:', style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.6)),
                        SizedBox(height: 8),
                        Text('http://192.168.x.x:8000', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6366F1), fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 22),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
      ],
    );
  }
}
