import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

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
        'mime': file.asset.mime ?? _mimeFromAsset(file.asset),
        'name': _suggestedName(file),
      };
      if (action == 'copy' && !file.asset.isGif) {
        final decoded = image.decodeImage(file.bytes);
        if (decoded != null) {
          arguments['clipboardPng'] = Uint8List.fromList(
            image.encodePng(decoded),
          );
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
    final suffix = file.asset.isGif ? 'gif' : 'png';
    final sanitized = file.asset.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    return '${sanitized.isEmpty ? 'meme' : sanitized}.$suffix';
  }

  static String _mimeFromAsset(MemeAsset asset) =>
      asset.isGif ? 'image/gif' : 'image/png';
}
