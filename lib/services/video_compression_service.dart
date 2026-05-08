import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class VideoCompressResult {
  final File file;
  final int originalSize;
  final int compressedSize;
  final bool wasCompressed;

  VideoCompressResult({
    required this.file,
    required this.originalSize,
    required this.compressedSize,
    required this.wasCompressed,
  });

  double get compressionRatio =>
      originalSize > 0 ? (1 - compressedSize / originalSize) * 100 : 0;

  String get originalSizeMB => (originalSize / (1024 * 1024)).toStringAsFixed(1);
  String get compressedSizeMB => (compressedSize / (1024 * 1024)).toStringAsFixed(1);
}

class VideoCompressionService {
  static const List<String> _compressibleFormats = [
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.m4v',
    '.3gp',
    '.webm',
  ];

  static bool isCompressible(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return _compressibleFormats.contains(ext);
  }

  static bool _isLargeFile(String filePath) {
    final file = File(filePath);
    final sizeInBytes = file.lengthSync();
    final sizeInMB = sizeInBytes / (1024 * 1024);
    return sizeInMB > 50;
  }

  static Future<VideoCompressResult> compressVideo(
    File sourceFile, {
    Function(double progress)? onProgress,
    int quality = 23,
    bool forceCompress = false,
  }) async {
    final originalSize = await sourceFile.length();
    final originalSizeMB = originalSize / (1024 * 1024);

    if (!forceCompress && originalSizeMB < 50) {
      return VideoCompressResult(
        file: sourceFile,
        originalSize: originalSize,
        compressedSize: originalSize,
        wasCompressed: false,
      );
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = path.join(
        tempDir.path,
        'compressed_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      final result = await _compressWithMediaKit(
        sourceFile.path,
        outputPath,
        quality: quality,
        onProgress: onProgress,
        originalSize: originalSize,
      );

      if (result != null) {
        final compressedSize = await result.length();

        if (compressedSize < originalSize * 0.95) {
          return VideoCompressResult(
            file: result,
            originalSize: originalSize,
            compressedSize: compressedSize,
            wasCompressed: true,
          );
        } else {
          await result.delete();
        }
      }
    } catch (e) {
      debugPrint('Video compression failed: $e');
    }

    return VideoCompressResult(
      file: sourceFile,
      originalSize: originalSize,
      compressedSize: originalSize,
      wasCompressed: false,
    );
  }

  static Future<File?> _compressWithMediaKit(
    String inputPath,
    String outputPath, {
    required int quality,
    Function(double progress)? onProgress,
    required int originalSize,
  }) async {
    try {
      final process = await Process.start(
        'ffmpeg',
        [
          '-i', inputPath,
          '-c:v', 'libx264',
          '-crf', quality.toString(),
          '-preset', 'medium',
          '-c:a', 'aac',
          '-b:a', '128k',
          '-movflags', '+faststart',
          '-y',
          outputPath,
        ],
      );

      final exitCode = await process.exitCode;

      if (exitCode == 0 && File(outputPath).existsSync()) {
        return File(outputPath);
      }
    } catch (e) {
      debugPrint('FFmpeg error: $e');
    }
    return null;
  }

  static Future<bool> isFFmpegAvailable() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('compressed_')) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }
}
