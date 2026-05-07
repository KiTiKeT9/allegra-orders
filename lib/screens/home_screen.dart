import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'upload_screen.dart';
import 'settings_screen.dart';
import '../services/order_service.dart';
import '../services/update_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  String? _lastScannedCode;
  final TextEditingController _manualController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late AnimationController _pulseController;
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onQRCodeDetected(BarcodeCapture capture) {
    if (!_isScanning) return;
    for (final barcode in capture.barcodes) {
      final String? code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        setState(() { _lastScannedCode = code; _isScanning = false; });
        HapticFeedback.mediumImpact();
        _navigateToUpload(code);
        break;
      }
    }
  }

  void _navigateToUpload(String code) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => UploadScreen(orderNumber: code),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ).then((_) => setState(() => _isScanning = true));
  }

  Future<void> _scanQRFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      final controller = MobileScannerController();
      BarcodeCapture? capture;
      final subscription = controller.barcodes.listen((event) => capture = event);
      final bool success = await controller.analyzeImage(image.path);
      subscription.cancel();
      controller.dispose();

      if (success && capture != null && capture!.barcodes.isNotEmpty) {
        final String? code = capture?.barcodes.first.rawValue?.trim();
        if (code != null && code.isNotEmpty && mounted) {
          HapticFeedback.mediumImpact();
          _navigateToUpload(code);
        } else {
          _showSnack('QR-код не найден', isError: true);
        }
      } else {
        _showSnack('Не удалось распознать изображение', isError: true);
      }
    } catch (e) {
      _showSnack('Ошибка: $e', isError: true);
    }
  }

  void _showManualEntryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Введите номер заказа', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _manualController,
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Например: ORD-12345',
                prefixIcon: Icon(Icons.receipt_long, color: Color(0xFF6366F1)),
              ),
              onSubmitted: (value) => _submitManual(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitManual,
                child: const Text('Продолжить'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _submitManual() {
    final String code = _manualController.text.trim();
    if (code.isNotEmpty) {
      Navigator.pop(context);
      _navigateToUpload(code);
      _manualController.clear();
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/logo.png', width: 40, height: 40, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Allegra', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
                        Text('Сканер заказов', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pushNamed(context, '/settings'),
                    icon: const Icon(Icons.settings_outlined, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),

            // Scanner
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          onDetect: _onQRCodeDetected,
                          fit: BoxFit.cover,
                        ),
                        // Overlay
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withOpacity(0.3), Colors.transparent, Colors.black.withOpacity(0.3)],
                            ),
                          ),
                        ),
                        // Scan frame
                        Center(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 220 + (_pulseController.value * 10),
                                height: 220 + (_pulseController.value * 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF6366F1).withOpacity(0.5 + (_pulseController.value * 0.5)),
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _cornerMarker(top: true, left: true),
                                        _cornerMarker(top: true, left: false),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        _cornerMarker(top: false, left: true),
                                        _cornerMarker(top: false, left: false),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        // Hint
                        const Positioned(
                          bottom: 24, left: 0, right: 0,
                          child: Center(
                            child: Text(
                              'Наведите на QR-код заказа',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Галерея',
                      color: const Color(0xFF8B5CF6),
                      onTap: _scanQRFromGallery,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.keyboard_outlined,
                      label: 'Вручную',
                      color: const Color(0xFFF59E0B),
                      onTap: _showManualEntryDialog,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _cornerMarker({bool top = true, bool left = true}) {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: Color(0xFF6366F1), width: 3) : BorderSide.none,
          left: left ? const BorderSide(color: Color(0xFF6366F1), width: 3) : BorderSide.none,
          right: !left ? const BorderSide(color: Color(0xFF6366F1), width: 3) : BorderSide.none,
          bottom: !top ? const BorderSide(color: Color(0xFF6366F1), width: 3) : BorderSide.none,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
