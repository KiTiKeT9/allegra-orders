import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:video_compress/video_compress.dart';

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
    '.mp4', '.mov', '.avi', '.mkv', '.m4v', '.3gp', '.webm',
  ];

  static bool isCompressible(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return _compressibleFormats.contains(ext);
  }

  static Future<VideoCompressResult> compressVideo(
    File sourceFile, {
    Function(double progress)? onProgress,
  }) async {
    final originalSize = await sourceFile.length();
    final originalSizeMB = originalSize / (1024 * 1024);

    if (originalSizeMB < 5) {
      return VideoCompressResult(
        file: sourceFile,
        originalSize: originalSize,
        compressedSize: originalSize,
        wasCompressed: false,
      );
    }

    Subscription? progressSubscription;

    try {
      if (onProgress != null) {
        onProgress(0);
        progressSubscription = VideoCompress.compressProgress$.subscribe((progress) {
          onProgress((progress / 100).clamp(0.0, 1.0));
        });
      }

      final compressionQuality = _getCompressionQuality(originalSizeMB);

      final MediaInfo? result = await VideoCompress.compressVideo(
        sourceFile.path,
        quality: compressionQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      progressSubscription?.unsubscribe();
      onProgress?.call(1.0);

      if (result != null && result.file != null) {
        final compressedFile = File(result.file!.path);
        final compressedSize = await compressedFile.length();

        return VideoCompressResult(
          file: compressedFile,
          originalSize: originalSize,
          compressedSize: compressedSize,
          wasCompressed: true,
        );
      }
    } catch (e) {
      progressSubscription?.unsubscribe();
      debugPrint('Video compression failed: $e');
    }

    return VideoCompressResult(
      file: sourceFile,
      originalSize: originalSize,
      compressedSize: originalSize,
      wasCompressed: false,
    );
  }

  static VideoQuality _getCompressionQuality(double sizeInMB) {
    if (sizeInMB > 1000) {
      return VideoQuality.LowQuality;
    } else if (sizeInMB > 500) {
      return VideoQuality.MediumQuality;
    } else {
      return VideoQuality.DefaultQuality;
    }
  }

  static Future<void> dispose() async {
    await VideoCompress.deleteAllCache();
  }
}
