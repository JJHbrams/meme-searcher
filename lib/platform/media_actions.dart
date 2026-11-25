import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../core/media_inspector.dart';
import '../core/models.dart';

/// Result returned after a user-triggered native media action.
class MediaActionResult {
  const MediaActionResult._({
    required this.completed,
    this.cancelled = false,
    this.mode,
    this.message,
  });

  const MediaActionResult.success({String? mode, String? message})
    : this._(completed: true, mode: mode, message: message);

  const MediaActionResult.cancelled({String? message})
    : this._(completed: false, cancelled: true, message: message);

  final bool completed;
  final bool cancelled;
  final String? mode;
  final String? message;

  factory MediaActionResult.fromPlatform(Object? value) {
    if (value is Map) {
      if (value['cancelled'] == true) {
        return MediaActionResult.cancelled(
          message: value['message'] as String?,
        );
      }
      return MediaActionResult.success(
        mode: value['mode'] as String?,
        message: value['message'] as String?,
      );
    }
    return const MediaActionResult.success();
  }
}

class MediaActionException implements Exception {
  const MediaActionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Performs native copy, share, and save operations for an already prepared
/// media file. Call these only from an explicit user gesture.
class MediaActions {
  MediaActions({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'dev.memesearcher.meme_searcher/media_actions';

  final MethodChannel _channel;

  Future<MediaActionResult> copy(MediaFile file) => _invoke('copy', file);

  Future<MediaActionResult> copyFile(MediaFile file) =>
      _invoke('copyFile', file);

  Future<MediaActionResult> share(MediaFile file) => _invoke('share', file);

  Future<MediaActionResult> save(MediaFile file) => _invoke('save', file);

  Future<MediaActionResult> _invoke(String action, MediaFile file) async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw const MediaActionException('이 기능은 Windows 또는 Android에서만 지원돼요.');
    }
    if (file.path.trim().isEmpty) {
      throw const MediaActionException('원본 파일을 먼저 준비해야 해요.');
    }

    try {
      final arguments = <String, Object?>{
        'path': file.path,
        'mime': _mimeForFile(file),
        'name': _suggestedName(file),
      };
      if (action == 'copy' && !file.asset.isGif) {
        if (MediaInspector.signatureFormat(file.bytes) == 'PNG') {
          arguments['clipboardPng'] = file.bytes;
        } else {
          // Windows can still decode the original through WIC.
          try {
            final decoded = image.decodeImage(file.bytes);
            if (decoded != null) {
              arguments['clipboardPng'] = image.encodePng(decoded);
            }
          } catch (_) {}
        }
      }
      final result = await _channel.invokeMethod<Object?>(action, arguments);
      return MediaActionResult.fromPlatform(result);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return MediaActionResult.cancelled(message: error.message);
      }
      throw MediaActionException(
        error.message ?? '작업을 완료하지 못했어요.',
        code: error.code,
      );
    } on MissingPluginException {
      throw const MediaActionException('이 기기에서는 원본 파일 작업을 사용할 수 없어요.');
    }
  }

  static String _suggestedName(MediaFile file) {
    final basename = file.path.split(RegExp(r'[\\/]')).last;
    if (basename.isNotEmpty && basename.contains('.')) {
      return basename;
    }
    final suffix = switch (_mimeForFile(file)) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'bin',
    };
    final sanitized = file.asset.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    return '${sanitized.isEmpty ? 'meme' : sanitized}.$suffix';
  }

  static String _mimeForFile(MediaFile file) {
    final format = (file.asset.format ?? '').trim().toUpperCase();
    if (file.asset.verified) {
      final verifiedMime = _mimeForFormat(format);
      if (verifiedMime != null) return verifiedMime;
    }

    final basename = file.path.split(RegExp(r'[\\/]')).last;
    final dot = basename.lastIndexOf('.');
    final fromExtension = dot < 0
        ? null
        : _mimeForFormat(basename.substring(dot + 1).toUpperCase());
    if (fromExtension != null) return fromExtension;

    final fromFormat = _mimeForFormat(format);
    if (fromFormat != null) return fromFormat;
    final fromHint = _mimeForFormat(
      (file.asset.formatHint ?? '').trim().toUpperCase(),
    );
    if (fromHint != null) return fromHint;

    const supported = <String>{
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
    };
    final declared = file.asset.mime?.toLowerCase();
    return supported.contains(declared)
        ? declared!
        : 'application/octet-stream';
  }

  static String? _mimeForFormat(String format) => switch (format) {
    'JPG' || 'JPEG' => 'image/jpeg',
    'PNG' => 'image/png',
    'WEBP' => 'image/webp',
    'GIF' => 'image/gif',
    _ => null,
  };
}
