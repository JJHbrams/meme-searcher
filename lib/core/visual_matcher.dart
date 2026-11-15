// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Verifies downloaded pixels against local, reference-only signatures.
/// A score is returned only after all conservative visual thresholds pass.
class VisualMatcher {
  VisualMatcher(this._references);
  final Map<String, List<_Reference>> _references;

  static Future<VisualMatcher> load(AssetBundle bundle) async {
    final raw = jsonDecode(
      await bundle.loadString('assets/meme-signatures.json'),
    ) as Map<String, dynamic>;
    final references = <String, List<_Reference>>{};
    for (final item
        in (raw['signatures'] as List? ?? const []).whereType<Map>()) {
      final family = item['familyId'] as String?;
      final features = item['features'];
      if (family == null || features is! Map) continue;
      try {
        final required = (item['requiredTags'] as List? ?? const [])
            .whereType<String>()
            .map(_normalize)
            .toSet();
        final gray = base64Decode(features['gray32'] as String)
            .map((value) => (value - 127.5) / 42.5)
            .toList(growable: false);
        final rgb = Uint8List.fromList(
          base64Decode(features['rgb16'] as String),
        );
        final hash = BigInt.parse(features['dhash'] as String, radix: 16);
        if (gray.length != 32 * 32 || rgb.length != 16 * 16 * 3) continue;
        (references[family] ??= []).add(_Reference(required, gray, rgb, hash));
      } catch (_) {
        // Malformed signatures never validate arbitrary results.
      }
    }
    return VisualMatcher(references);
  }

  Future<num?> score(
    Uint8List bytes,
    String? familyId, {
    Iterable<String> tags = const [],
  }) async {
    if (familyId == null) return null;
    final candidates = _references[familyId];
    if (candidates == null || candidates.isEmpty) return null;
    return Isolate.run(
      () => _scoreBytes(bytes, candidates, tags.map(_normalize).toSet()),
    );
  }
}

class _Reference {
  const _Reference(this.requiredTags, this.gray, this.rgb, this.hash);
  final Set<String> requiredTags;
  final List<double> gray;
  final Uint8List rgb;
  final BigInt hash;
}

num? _scoreBytes(
  Uint8List bytes,
  List<_Reference> references,
  Set<String> submittedTags,
) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    num? bestScore;
    for (final reference in references) {
      if (!submittedTags.containsAll(reference.requiredTags)) continue;
      _Comparison? best;
      for (final frame in _sampleFrames(decoded)) {
        final comparison = _compare(frame, reference);
        if (comparison != null &&
            (best == null || comparison.grayRmse < best.grayRmse))
          best = comparison;
      }
      if (best != null &&
          best.grayRmse <= .32 &&
          best.colorRmse <= .10 &&
          best.hashDistance <= 12 &&
          (bestScore == null || best.score > bestScore))
        bestScore = best.score;
    }
    return bestScore;
  } catch (_) {
    return null;
  }
}

List<img.Image> _sampleFrames(img.Image image) {
  final count = math.min(4, image.numFrames);
  if (count <= 1) return [image];
  final indexes = <int>{
    for (var index = 0; index < count; index++)
      (index * (image.numFrames - 1) / (count - 1)).round(),
  }.toList()..sort();
  return indexes.map(image.getFrame).toList(growable: false);
}

_Comparison? _compare(img.Image frame, _Reference reference) {
  final grayRgb = _resizedFlattenedRgb(frame, 32);
  final colorRgb = _resizedFlattenedRgb(frame, 16);
  if (grayRgb == null || colorRgb == null) return null;
  final gray = _normalizedGray(grayRgb);
  if (gray.length != reference.gray.length ||
      colorRgb.length != reference.rgb.length)
    return null;
  var graySquared = 0.0;
  for (var index = 0; index < gray.length; index++) {
    final delta = gray[index] - reference.gray[index];
    graySquared += delta * delta;
  }
  var colorSquared = 0.0;
  for (var index = 0; index < colorRgb.length; index++) {
    final delta = (colorRgb[index] - reference.rgb[index]) / 255.0;
    colorSquared += delta * delta;
  }
  final grayRmse = math.sqrt(graySquared / gray.length);
  final colorRmse = math.sqrt(colorSquared / colorRgb.length);
  final hashDistance = _bitCount(_dhash(colorRgb) ^ reference.hash);
  final score = math.max<double>(
    0.0,
    1 -
        (.62 * math.min(1, grayRmse / .70) +
            .28 * math.min(1, colorRmse / .20) +
            .10 * math.min(1, hashDistance / 18)),
  );
  return _Comparison(grayRmse, colorRmse, hashDistance, score);
}

Uint8List? _resizedFlattenedRgb(img.Image source, int size) {
  if (source.width <= 0 || source.height <= 0) return null;
  final flattened = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final alpha = pixel.a / 255.0;
      flattened.setPixelRgb(
        x,
        y,
        (pixel.r * alpha + 255 * (1 - alpha)).round(),
        (pixel.g * alpha + 255 * (1 - alpha)).round(),
        (pixel.b * alpha + 255 * (1 - alpha)).round(),
      );
    }
  }
  // package:image has no Lanczos; cubic is its closest stable high-quality option.
  final resized = img.copyResize(
    flattened,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  final result = Uint8List(size * size * 3);
  var offset = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final pixel = resized.getPixel(x, y);
      result[offset++] = pixel.r.toInt();
      result[offset++] = pixel.g.toInt();
      result[offset++] = pixel.b.toInt();
    }
  }
  return result;
}

List<double> _normalizedGray(Uint8List rgb) {
  final values = List<double>.filled(rgb.length ~/ 3, 0);
  var sum = 0.0;
  for (var index = 0; index < values.length; index++) {
    final offset = index * 3;
    final value =
        .299 * rgb[offset] + .587 * rgb[offset + 1] + .114 * rgb[offset + 2];
    values[index] = value;
    sum += value;
  }
  final average = sum / values.length;
  var squared = 0.0;
  for (final value in values) squared += (value - average) * (value - average);
  final deviation = math.sqrt(squared / values.length);
  if (deviation < 1) return List<double>.filled(values.length, 0);
  return values
      .map((value) => (value - average) / deviation)
      .toList(growable: false);
}

BigInt _dhash(Uint8List rgb) {
  final values = _normalizedGray(rgb);
  final luma = img.Image(width: 16, height: 16, numChannels: 1);
  for (var index = 0; index < values.length; index++) {
    final value = (values[index] * 40 + 128).round().clamp(0, 255);
    luma.setPixelRgb(index % 16, index ~/ 16, value, value, value);
  }
  final thumb = img.copyResize(
    luma,
    width: 9,
    height: 8,
    interpolation: img.Interpolation.cubic,
  );
  var bits = BigInt.zero;
  for (var y = 0; y < 8; y++)
    for (var x = 0; x < 8; x++) {
      bits =
          (bits << 1) |
          (thumb.getPixel(x, y).r > thumb.getPixel(x + 1, y).r
              ? BigInt.one
              : BigInt.zero);
    }
  return bits;
}

int _bitCount(BigInt value) {
  var count = 0;
  while (value != BigInt.zero) {
    count++;
    value &= value - BigInt.one;
  }
  return count;
}

String _normalize(String value) => value.trim().toLowerCase();

class _Comparison {
  const _Comparison(
    this.grayRmse,
    this.colorRmse,
    this.hashDistance,
    this.score,
  );
  final double grayRmse;
  final double colorRmse;
  final int hashDistance;
  final double score;
}
