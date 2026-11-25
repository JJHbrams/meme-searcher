// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:typed_data';
import 'dart:isolate';

import 'package:image/image.dart' as img;

class MediaInspection {
  const MediaInspection({
    required this.format,
    required this.width,
    required this.height,
    required this.frames,
    required this.animated,
    required this.motionVerified,
    required this.reason,
  });
  final String format;
  final int? width;
  final int? height;
  final int frames;
  final bool animated;
  final bool motionVerified;
  final String reason;
}

/// Header-level inspection deliberately avoids decoding untrusted animation
/// frames. It bounds work before a renderer ever sees an original GIF.
class MediaInspector {
  static const maxPixels = 4000000;
  static const maxAnimationPixels = 64000000;

  static String? signatureFormat(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final start = String.fromCharCodes(bytes, 0, 6);
    if (start == 'GIF87a' || start == 'GIF89a') return 'GIF';
    if (start.startsWith('\x89PNG\r\n') && bytes[6] == 26 && bytes[7] == 10)
      return 'PNG';
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return 'JPEG';
    if (start.startsWith('RIFF') &&
        String.fromCharCodes(bytes, 8, 12) == 'WEBP')
      return 'WEBP';
    if (String.fromCharCodes(bytes, 4, 8) == 'ftyp' &&
        {'avif', 'avis'}.contains(String.fromCharCodes(bytes, 8, 12)))
      return 'AVIF';
    return null;
  }

  static MediaInspection inspect(Uint8List bytes) {
    final format = signatureFormat(bytes);
    if (bytes.length >= 13 && format == 'GIF') return _gif(bytes);
    if (bytes.length >= 24 && format == 'PNG') {
      final width = _u32(bytes, 16);
      final height = _u32(bytes, 20);
      return MediaInspection(
        format: 'PNG',
        width: width,
        height: height,
        frames: 1,
        animated: false,
        motionVerified: false,
        reason: _validCanvas(width, height) ? 'static' : 'canvas-too-large',
      );
    }
    if (format == 'WEBP') {
      final webp = _webp(bytes);
      final animated = webp.$3 > 1;
      return MediaInspection(
        format: 'WEBP',
        width: webp.$1,
        height: webp.$2,
        frames: webp.$3,
        animated: animated,
        motionVerified: false,
        reason: !_validCanvas(webp.$1 ?? 0, webp.$2 ?? 0)
            ? 'canvas-too-large'
            : animated &&
                  ((webp.$1 ?? 0) * (webp.$2 ?? 0) * webp.$3 >
                      maxAnimationPixels)
            ? 'animation-budget-exceeded'
            : animated
            ? 'motion-unverified'
            : 'static',
      );
    }
    final jpeg = _jpeg(bytes);
    if (jpeg != null) {
      return MediaInspection(
        format: 'JPEG',
        width: jpeg.$1,
        height: jpeg.$2,
        frames: 1,
        animated: false,
        motionVerified: false,
        reason: _validCanvas(jpeg.$1, jpeg.$2) ? 'static' : 'canvas-too-large',
      );
    }
    return const MediaInspection(
      format: 'UNKNOWN',
      width: null,
      height: null,
      frames: 0,
      animated: false,
      motionVerified: false,
      reason: 'unsupported',
    );
  }

  static Future<MediaInspection> inspectMotion(Uint8List bytes) =>
      Isolate.run(() => _inspectMotion(bytes));

  static MediaInspection _inspectMotion(Uint8List bytes) {
    final header = inspect(bytes);
    if (!header.animated || header.format != 'GIF') return header;
    try {
      final decoded = img.decodeGif(bytes);
      if (decoded == null || decoded.numFrames < 2)
        return MediaInspection(
          format: header.format,
          width: header.width,
          height: header.height,
          frames: header.frames,
          animated: false,
          motionVerified: false,
          reason: 'undecodable-animation',
        );
      final indexes = <int>{
        0,
        decoded.numFrames ~/ 3,
        (decoded.numFrames * 2) ~/ 3,
        decoded.numFrames - 1,
      }.toList()..sort();
      final samples = indexes
          .map(
            (index) => img
                .copyResize(
                  decoded.getFrame(index),
                  width: 48,
                  height: 48,
                  interpolation: img.Interpolation.cubic,
                )
                .getBytes(order: img.ChannelOrder.rgba),
          )
          .toList(growable: false);
      var changed = 0;
      final first = samples.first;
      for (final sample in samples.skip(1)) {
        for (var i = 0; i < first.length && i < sample.length; i += 4) {
          if (first[i] != sample[i] ||
              first[i + 1] != sample[i + 1] ||
              first[i + 2] != sample[i + 2] ||
              first[i + 3] != sample[i + 3])
            changed++;
        }
      }
      return MediaInspection(
        format: header.format,
        width: header.width,
        height: header.height,
        frames: header.frames,
        animated: true,
        motionVerified: changed > 2,
        reason: changed > 2 ? 'pixel-motion' : 'identical-frames',
      );
    } catch (_) {
      return MediaInspection(
        format: header.format,
        width: header.width,
        height: header.height,
        frames: header.frames,
        animated: true,
        motionVerified: false,
        reason: 'motion-unverified',
      );
    }
  }

  static MediaInspection _gif(Uint8List b) {
    final width = b[6] | (b[7] << 8);
    final height = b[8] | (b[9] << 8);
    if (!_validCanvas(width, height))
      return MediaInspection(
        format: 'GIF',
        width: width,
        height: height,
        frames: 0,
        animated: false,
        motionVerified: false,
        reason: 'canvas-too-large',
      );
    var position = 13;
    if ((b[10] & 0x80) != 0) position += 3 * (1 << ((b[10] & 7) + 1));
    var frames = 0;
    while (position < b.length && frames <= 500) {
      final marker = b[position++];
      if (marker == 0x2c) {
        // image descriptor
        if (position + 9 > b.length) break;
        position += 8;
        final packed = b[position++];
        if ((packed & 0x80) != 0) position += 3 * (1 << ((packed & 7) + 1));
        if (position >= b.length) break;
        position++; // LZW minimum code size
        while (position < b.length) {
          final size = b[position++];
          if (size == 0) break;
          position += size;
          if (position > b.length) break;
        }
        frames++;
      } else if (marker == 0x21) {
        if (position >= b.length) break;
        position++; // extension label
        while (position < b.length) {
          final size = b[position++];
          if (size == 0) break;
          position += size;
          if (position > b.length) break;
        }
      } else if (marker == 0x3b)
        break;
    }
    final budget = width * height * frames;
    final animated =
        frames > 1 && frames <= 500 && budget <= maxAnimationPixels;
    return MediaInspection(
      format: 'GIF',
      width: width,
      height: height,
      frames: frames,
      animated: animated,
      motionVerified: animated,
      reason: animated
          ? 'multi-frame'
          : frames > 500 || budget > maxAnimationPixels
          ? 'animation-budget-exceeded'
          : 'single-frame',
    );
  }

  static bool _validCanvas(int width, int height) =>
      width > 0 && height > 0 && width * height <= maxPixels;
  static (int, int)? _jpeg(Uint8List b) {
    if (b.length < 4 || b[0] != 0xff || b[1] != 0xd8) return null;
    var at = 2;
    while (at + 9 < b.length) {
      if (b[at++] != 0xff) continue;
      while (at < b.length && b[at] == 0xff) at++;
      if (at >= b.length) return null;
      final marker = b[at++];
      if (marker == 0xd8 ||
          marker == 0xd9 ||
          (marker >= 0xd0 && marker <= 0xd7))
        continue;
      if (at + 2 > b.length) return null;
      final length = (b[at] << 8) | b[at + 1];
      if (length < 2 || at + length > b.length) return null;
      final sof =
          (marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf);
      if (sof && length >= 8)
        return ((b[at + 3] << 8) | b[at + 4], (b[at + 5] << 8) | b[at + 6]);
      at += length;
    }
    return null;
  }

  static (int?, int?, int) _webp(Uint8List b) {
    int? width;
    int? height;
    var frames = 0;
    var at = 12;
    while (at + 8 <= b.length) {
      final type = String.fromCharCodes(b.sublist(at, at + 4));
      final length =
          b[at + 4] | (b[at + 5] << 8) | (b[at + 6] << 16) | (b[at + 7] << 24);
      final data = at + 8;
      if (length < 0 || data + length > b.length) break;
      if (type == 'VP8X' && length >= 10) {
        width = 1 + b[data + 4] + (b[data + 5] << 8) + (b[data + 6] << 16);
        height = 1 + b[data + 7] + (b[data + 8] << 8) + (b[data + 9] << 16);
      } else if (type == 'VP8 ' &&
          length >= 10 &&
          b[data + 3] == 0x9d &&
          b[data + 4] == 0x01 &&
          b[data + 5] == 0x2a) {
        width ??= (b[data + 6] | (b[data + 7] << 8)) & 0x3fff;
        height ??= (b[data + 8] | (b[data + 9] << 8)) & 0x3fff;
      } else if (type == 'VP8L' && length >= 5 && b[data] == 0x2f) {
        final bits =
            b[data + 1] |
            (b[data + 2] << 8) |
            (b[data + 3] << 16) |
            (b[data + 4] << 24);
        width ??= 1 + (bits & 0x3fff);
        height ??= 1 + ((bits >> 14) & 0x3fff);
      } else if (type == 'ANMF') {
        frames++;
      }
      at = data + length + (length.isOdd ? 1 : 0);
    }
    return (width, height, frames == 0 ? 1 : frames);
  }

  static int _u32(Uint8List b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
}
