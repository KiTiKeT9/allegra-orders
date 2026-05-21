import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/order_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  Map<String, dynamic> _diskInfo = {};
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final service = Provider.of<OrderService>(context, listen: false);
      final results = await Future.wait([
        http.get(Uri.parse('${service.serverUrl}/api/orders')).timeout(const Duration(seconds: 10)),
        service.getDiskInfo(),
      ]);

      final response = results[0] as http.Response;
      final diskInfo = results[1] as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _orders = data['orders'] ?? [];
          _diskInfo = diskInfo;
          _isLoading = false;
        });
      } else {
        setState(() { _error = 'Ошибка сервера: ${response.statusCode}'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Ошибка сети: $e'; _isLoading = false; });
    }
  }

  List<dynamic> get _filteredOrders {
    if (_searchQuery.isEmpty) return _orders;
    return _orders.where((o) {
      final num = (o['order_number'] ?? '').toString().toLowerCase();
      final date = (o['created_at'] ?? '').toString().toLowerCase();
      return num.contains(_searchQuery.toLowerCase()) || date.contains(_searchQuery.toLowerCase());
    }).toList();
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
                    child: Text('Заказы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
                  ),
                  IconButton(
                    onPressed: _loadOrders,
                    icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Color(0xFFF1F5F9)),
                decoration: InputDecoration(
                  hintText: 'Поиск по номеру или дате...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
                  filled: true,
                  fillColor: const Color(0xFF161B2E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),

            const SizedBox(height: 12),

            // Disk info
            if (_diskInfo.isNotEmpty && _diskInfo['total'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _DiskInfoWidget(diskInfo: _diskInfo),
              ),

            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF6366F1)),
            SizedBox(height: 16),
            Text('Загрузка заказов...', style: TextStyle(color: Color(0xFF94A3B8))),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadOrders,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final orders = _filteredOrders;

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, color: Color(0xFF64748B), size: 48),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'Заказов нет' : 'Ничего не найдено',
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: const Color(0xFF6366F1),
      backgroundColor: const Color(0xFF161B2E),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return _OrderCard(
            order: order,
            onTap: () => _showOrderDetails(order),
          );
        },
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final service = Provider.of<OrderService>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _OrderDetailsSheet(order: order, service: service),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final orderNumber = order['order_number'] ?? '—';
    final date = order['created_at'] != null
        ? DateTime.parse(order['created_at']).toLocal().toString().substring(0, 16)
        : '—';
    final totalCount = order['total_count'] ?? 0;
    final damaged = order['damaged'] ?? 0;
    final issues = order['issues'] ?? 0;
    final filesCount = order['files_count'] ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inventory_2, color: Color(0xFF6366F1), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(orderNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
                      Text('Создан: $date', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatBadge(label: 'Всего', value: '$totalCount', color: const Color(0xFF6366F1)),
                const SizedBox(width: 8),
                _StatBadge(label: 'Разбито', value: '$damaged', color: const Color(0xFFEF4444)),
                const SizedBox(width: 8),
                _StatBadge(label: 'Проблемы', value: '$issues', color: const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                _StatBadge(label: 'Файлы', value: '$filesCount', color: const Color(0xFF10B981)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

class _OrderDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final OrderService service;

  const _OrderDetailsSheet({required this.order, required this.service});

  @override
  State<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends State<_OrderDetailsSheet> {
  final Set<String> _downloadingFiles = {};
  final Map<String, double> _downloadProgress = {};

  Future<void> _downloadFile(String filePath) async {
    if (_downloadingFiles.contains(filePath)) return;
    setState(() {
      _downloadingFiles.add(filePath);
      _downloadProgress[filePath] = 0;
    });
    final orderNumber = widget.order['order_number'] ?? '';
    final path = await widget.service.downloadFile(
      orderNumber, filePath,
      onProgress: (progress) {
        if (mounted) setState(() => _downloadProgress[filePath] = progress);
      },
    );
    if (mounted) {
      setState(() {
        _downloadingFiles.remove(filePath);
        _downloadProgress.remove(filePath);
      });
      if (path != null) {
        _openFile(path);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка скачивания'), backgroundColor: Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _openFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final dir = await getApplicationDocumentsDirectory();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сохранено: ${path.split('/').last}'),
          backgroundColor: const Color(0xFF10B981),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderNumber = widget.order['order_number'] ?? '—';
    final files = (widget.order['files'] as List?) ?? [];
    final notes = widget.order['notes'] ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
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
            Text(orderNumber, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9))),
            const SizedBox(height: 16),

            // Stats
            Row(
              children: [
                _DetailStat(label: 'Всего', value: '${widget.order['total_count'] ?? 0}'),
                _DetailStat(label: 'Разбито', value: '${widget.order['damaged'] ?? 0}'),
                _DetailStat(label: 'Проблемы', value: '${widget.order['issues'] ?? 0}'),
              ],
            ),

            const SizedBox(height: 20),
            const Text('Файлы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFF1F5F9))),
            const SizedBox(height: 12),

            // Files list
            Expanded(
              child: files.isEmpty
                  ? Center(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          const SizedBox(height: 100),
                          const Center(child: Text('Нет файлов', style: TextStyle(color: Color(0xFF64748B)))),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Text('Заметки', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFF1F5F9))),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF0B0F19), borderRadius: BorderRadius.circular(10)),
                              child: Text(notes, style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: files.length + (notes.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                          if (index < files.length) {
                            final file = files[index].toString();
                            final isVideo = file.endsWith('.mp4') || file.endsWith('.mov') || file.endsWith('.avi') || file.endsWith('.mkv');
                            final isDownloading = _downloadingFiles.contains(file);
                            final progress = _downloadProgress[file] ?? 0.0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF0B0F19), borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                children: [
                                  Icon(isVideo ? Icons.videocam : Icons.image,
                                      color: isVideo ? const Color(0xFF8B5CF6) : const Color(0xFF10B981), size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(file.split('/').last, style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis)),
                                  if (isDownloading)
                                    SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                        value: progress > 0 ? progress : null,
                                        strokeWidth: 2,
                                        color: const Color(0xFF6366F1),
                                      ),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.download, color: Color(0xFF6366F1), size: 20),
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _downloadFile(file),
                                    ),
                                ],
                              ),
                            );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Заметки', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFF1F5F9))),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFF0B0F19), borderRadius: BorderRadius.circular(10)),
                                child: Text(notes, style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;

  const _DetailStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F19),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }
}

class _DiskInfoWidget extends StatelessWidget {
  final Map<String, dynamic> diskInfo;

  const _DiskInfoWidget({required this.diskInfo});

  @override
  Widget build(BuildContext context) {
    final total = (diskInfo['total'] as num?)?.toDouble() ?? 0;
    final free = (diskInfo['free'] as num?)?.toDouble() ?? 0;
    final used = (diskInfo['used'] as num?)?.toDouble() ?? 0;
    final percentUsed = (diskInfo['percentUsed'] as num?)?.toInt() ?? 0;

    final percentColor = percentUsed > 90
        ? const Color(0xFFEF4444)
        : percentUsed > 70
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              const Text('Место на диске', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFF1F5F9))),
              const Spacer(),
              Text('${free.toStringAsFixed(1)} ГБ свободно',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: percentColor)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentUsed / 100,
              backgroundColor: const Color(0xFF0B0F19),
              valueColor: AlwaysStoppedAnimation<Color>(percentColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Использовано: ${used.toStringAsFixed(1)} ГБ',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              Text('Всего: ${total.toStringAsFixed(1)} ГБ',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ],
      ),
    );
  }
}
