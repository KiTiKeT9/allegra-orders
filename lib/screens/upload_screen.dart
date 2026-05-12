import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/order_service.dart';
import '../services/video_compression_service.dart';

class UploadScreen extends StatefulWidget {
  final String orderNumber;
  const UploadScreen({super.key, required this.orderNumber});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedFiles = [];
  bool _isUploading = false;
  int _count = 1;
  int _windowNumber = 1;
  bool _appendMode = false;
  bool _orderExists = false;
  int _orderWindowsCount = 0;
  bool _isChecking = true;
  bool _isCompressing = false;
  double _compressProgress = 0;
  String _compressStatus = '';
  double _uploadProgress = 0;
  String _uploadStatus = '';
  final TextEditingController _countController = TextEditingController(text: '1');
  final TextEditingController _windowController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _checkOrderExists();
  }

  Future<void> _checkOrderExists() async {
    if (widget.orderNumber.isEmpty) {
      _showSnack('Ошибка: Номер заказа пуст!', isError: true);
      Navigator.pop(context);
      return;
    }

    final service = Provider.of<OrderService>(context, listen: false);
    final result = await service.checkOrderExists(widget.orderNumber);

    setState(() {
      _orderExists = result['exists'] as bool;
      _orderWindowsCount = result['windowsCount'] as int;
      _isChecking = false;
      _appendMode = _orderExists;
      if (_orderExists) {
        _count = 0;
        _countController.text = '0';
      }
    });
  }

  Future<void> _pickImages() async {
    final List<XFile>? images = await _picker.pickMultiImage();
    if (images != null) setState(() => _selectedFiles.addAll(images));
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) setState(() => _selectedFiles.add(video));
  }

  void _removeFile(int index) => setState(() => _selectedFiles.removeAt(index));

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty) {
      _showSnack('Выберите файлы для загрузки', isError: true);
      return;
    }
    setState(() => _isUploading = true);

    try {
      final processedFiles = <XFile>[];
      int totalSaved = 0;

      for (int i = 0; i < _selectedFiles.length; i++) {
        final file = _selectedFiles[i];
        if (VideoCompressionService.isCompressible(file.path)) {
          setState(() {
            _isCompressing = true;
            _compressStatus = 'Сжатие видео ${i + 1} из ${_selectedFiles.length}...';
            _compressProgress = 0;
          });

          final result = await VideoCompressionService.compressVideo(
            File(file.path),
            onProgress: (p) => setState(() => _compressProgress = p),
          );

          if (result.wasCompressed) {
            processedFiles.add(XFile(result.file.path));
            totalSaved += result.originalSize - result.compressedSize;
            debugPrint('Video compressed: ${result.originalSizeMB}MB -> ${result.compressedSizeMB}MB (${result.compressionRatio.toStringAsFixed(1)}% saved)');
          } else {
            processedFiles.add(file);
          }
        } else {
          processedFiles.add(file);
        }
      }

      setState(() {
        _isCompressing = false;
        _compressStatus = '';
        _compressProgress = 0;
      });

      final service = Provider.of<OrderService>(context, listen: false);
      setState(() {
        _uploadStatus = 'Загрузка на сервер...';
        _uploadProgress = 0;
      });

      final success = await service.uploadOrder(
        widget.orderNumber,
        processedFiles,
        count: _appendMode ? 0 : _count,
        windowNumber: _windowNumber,
        appendMode: _appendMode,
        onProgress: (progress, sent, total) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
              final sentMB = (sent / (1024 * 1024)).toStringAsFixed(1);
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
              _uploadStatus = 'Загрузка: $sentMB / $totalMB МБ';
            });
          }
        },
      );

      if (mounted) {
        if (success) {
          final savedMB = (totalSaved / (1024 * 1024)).toStringAsFixed(1);
          final msg = totalSaved > 0
              ? 'Заказ ${widget.orderNumber} (окно $_windowNumber) отправлен! Сэкономлено: ${savedMB} МБ'
              : 'Заказ ${widget.orderNumber} (окно $_windowNumber) отправлен!';
          _showSnack(msg, isError: false);
          Future.delayed(const Duration(milliseconds: 1500), () => Navigator.pop(context));
        } else {
          _showSnack(service.lastError ?? 'Ошибка сервера', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Ошибка: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isCompressing = false;
          _uploadProgress = 0;
          _uploadStatus = '';
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFF161B2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  bool _checkIsVideo(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv');
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
                    child: Text('Загрузка', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
                  ),
                ],
              ),
            ),

            if (_isChecking)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF6366F1)),
                      SizedBox(height: 16),
                      Text('Проверка заказа...', style: TextStyle(color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Order card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: const Color(0x406366F1), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.receipt_long, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Номер заказа', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                      Text(
                                        widget.orderNumber.isEmpty ? '—' : widget.orderNumber,
                                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_orderExists) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                  'Заказ уже существует ($_orderWindowsCount ${_pluralize(_orderWindowsCount, 'окно', 'окна', 'окон')})',
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                child: const Text(
                                  'Новый заказ',
                                  style: TextStyle(fontSize: 12, color: Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Mode selection if order exists
                      if (_orderExists)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x1AFFFFFF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Режим загрузки', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                              const SizedBox(height: 12),
                              Row(
                              children: [
                                Expanded(
                                  child: _ModeButton(
                                    title: 'Новая запись',
                                    icon: Icons.fiber_new,
                                    selected: !_appendMode,
                                    onTap: () {
                                      setState(() {
                                        _appendMode = false;
                                        _count = _count == 0 ? 1 : _count;
                                        _countController.text = _count.toString();
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ModeButton(
                                    title: 'Добавить',
                                    icon: Icons.add_circle_outline,
                                    selected: _appendMode,
                                    onTap: () {
                                      setState(() {
                                        _appendMode = true;
                                        _count = 0;
                                        _countController.text = '0';
                                      });
                                    },
                                  ),
                                ),
                              ],
                              ),
                            ],
                          ),
                        ),

                      if (_orderExists) const SizedBox(height: 24),

                      // Window number
                      const Text('Номер окна', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _CountButton(
                            icon: Icons.remove,
                            onTap: () {
                              if (_windowNumber > 1) {
                                setState(() => _windowNumber--);
                                _windowController.text = _windowNumber.toString();
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _windowController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9)),
                              onChanged: (val) => setState(() => _windowNumber = int.tryParse(val) ?? 1),
                              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 16)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _CountButton(
                            icon: Icons.add,
                            onTap: () {
                              setState(() => _windowNumber++);
                              _windowController.text = _windowNumber.toString();
                            },
                          ),
                        ],
                      ),

                      // Count (hidden in append mode)
                      if (!_appendMode) ...[
                        const SizedBox(height: 24),
                        const Text('Количество коробок', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _CountButton(
                              icon: Icons.remove,
                              onTap: () {
                                if (_count > 0) {
                                  setState(() => _count--);
                                  _countController.text = _count.toString();
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _countController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9)),
                                onChanged: (val) => setState(() => _count = int.tryParse(val) ?? 0),
                                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 16)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _CountButton(
                              icon: Icons.add,
                              onTap: () {
                                setState(() => _count++);
                                _countController.text = _count.toString();
                              },
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Files grid
                      if (_selectedFiles.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Файлы (${_selectedFiles.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                            GestureDetector(
                              onTap: () => setState(() => _selectedFiles.clear()),
                              child: const Text('Очистить', style: TextStyle(fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10,
                          ),
                          itemCount: _selectedFiles.length,
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            final isVid = _checkIsVideo(file.path);
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (isVid)
                                    Container(
                                      color: const Color(0xFF161B2E),
                                      child: const Icon(Icons.videocam, color: Color(0xFF6366F1), size: 32),
                                    )
                                  else
                                    Image.file(File(file.path), fit: BoxFit.cover),
                                  Positioned(
                                    top: 6, right: 6,
                                    child: GestureDetector(
                                      onTap: () => _removeFile(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                                      ),
                                    ),
                                  ),
                                  if (isVid)
                                    const Positioned(
                                      bottom: 6, left: 6,
                                      child: Text('VIDEO', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700)),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Add buttons
                      Row(
                        children: [
                          Expanded(
                            child: _AddButton(
                              icon: Icons.add_photo_alternate_outlined,
                              label: 'Фото',
                              onTap: _pickImages,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _AddButton(
                              icon: Icons.videocam_outlined,
                              label: 'Видео',
                              onTap: _pickVideo,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),

            // Upload button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0F19),
                border: const Border(top: BorderSide(color: Color(0x1AFFFFFF))),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCompressing) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF6366F1),
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _compressStatus,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                                Text(
                                  '${(_compressProgress * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _compressProgress,
                                backgroundColor: const Color(0xFF0B0F19),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_isUploading) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF10B981),
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _uploadStatus,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                                Text(
                                  '${(_uploadProgress * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _uploadProgress,
                                backgroundColor: const Color(0xFF0B0F19),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isUploading || _isCompressing || _selectedFiles.isEmpty || _isChecking ? null : _uploadFiles,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          disabledBackgroundColor: const Color(0xFF10B981).withOpacity(0.3),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(
                                _appendMode ? 'Добавить к заказу' : 'Отправить заказ',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _pluralize(int count, String one, String few, String many) {
    if (count % 10 == 1 && count % 100 != 11) return one;
    if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) return few;
    return many;
  }
}

class _CountButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CountButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Icon(icon, color: const Color(0xFF94A3B8), size: 22),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF161B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF6366F1), size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6366F1) : const Color(0xFF0B0F19),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? const Color(0xFF6366F1) : const Color(0x1AFFFFFF)),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : const Color(0xFF94A3B8), size: 24),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
