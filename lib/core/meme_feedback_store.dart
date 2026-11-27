import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'ranking_service.dart';

/// Explicit feedback retained by the MCP drawer for results the app has
/// already returned. This intentionally does not infer anything from result
/// titles or generated text.
enum MemeFeedbackKind { helpful, wrong, correction }

class MemeFeedbackStore {
  MemeFeedbackStore._(this._file, this._entries, this._writable);

  static const _fileName = 'meme-feedback-v1.json';
  static const _version = 1;

  final File _file;
  final bool _writable;
  Map<String, _FeedbackEntry> _entries;
  Future<void> _commitTail = Future.value();

  /// Opens the feedback file stored beside the user's meme drawer assets.
  /// Invalid or newer files are left untouched for recovery.
  static Future<MemeFeedbackStore> open(Directory directory) async {
    final file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    final entries = <String, _FeedbackEntry>{};
    var writable = true;
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map && raw['version'] == _version && raw['queries'] is Map) {
          for (final entry in (raw['queries'] as Map).entries) {
            final key = entry.key.toString();
            final value = _FeedbackEntry.fromJson(entry.value);
            if (key.isNotEmpty && value != null) entries[key] = value;
          }
        } else {
          writable = false;
        }
      } on FileSystemException {
        // The drawer remains usable if the feedback file is briefly unreadable.
        writable = false;
      } on FormatException {
        writable = false;
      }
    }
    return MemeFeedbackStore._(file, entries, writable);
  }

  /// Returns an explicit correction for this search phrase, if one was saved.
  String? correctedQueryFor(String query) {
    return _entries[_normalizeQuery(query)]?.correction;
  }

  /// Applies only feedback for this normalized search phrase. The original
  /// search order is preserved within positive, neutral, and negative groups.
  List<MemeAsset> rerank(String query, List<MemeAsset> assets) {
    final entry = _entries[_normalizeQuery(query)];
    if (entry == null || assets.length < 2) return assets;
    final positive = <MemeAsset>[];
    final neutral = <MemeAsset>[];
    final negative = <MemeAsset>[];
    for (final asset in assets) {
      switch (entry.votes[candidateKey(asset)]) {
        case MemeFeedbackKind.helpful:
          positive.add(asset);
        case MemeFeedbackKind.wrong:
          negative.add(asset);
        case MemeFeedbackKind.correction:
        case null:
          neutral.add(asset);
      }
    }
    return [...positive, ...neutral, ...negative];
  }

  /// Records a deliberate user action. A correction marks the recommended
  /// candidate as rejected and associates the supplied lookup phrase with the
  /// recommendation query; an explicit alias receives the same association.
  Future<void> record({
    required String query,
    required MemeAsset asset,
    required MemeFeedbackKind kind,
    String? correction,
    String? alias,
  }) {
    final queryKey = _normalizeQuery(query);
    final correctionValue = correction?.trim();
    final aliasKey = _normalizeQuery(alias ?? '');
    if (!_writable) {
      throw StateError('Cannot update unreadable feedback rules.');
    }
    if (queryKey.isEmpty ||
        (alias != null && aliasKey.isEmpty) ||
        (kind == MemeFeedbackKind.correction &&
            (correctionValue == null ||
                _normalizeQuery(correctionValue).isEmpty))) {
      throw const FormatException(
        'A search phrase and valid correction are required.',
      );
    }

    final commit = _commitTail.then((_) async {
      final next = _copyEntries(_entries);
      var target = (next[queryKey] ?? const _FeedbackEntry()).copy();
      final candidate = candidateKey(asset);
      if (kind == MemeFeedbackKind.correction) {
        target = _FeedbackEntry(
          correction: correctionValue,
          votes: Map<String, MemeFeedbackKind>.from(target.votes),
        );
        target.votes[candidate] = MemeFeedbackKind.wrong;
      } else {
        target.votes[candidate] = kind;
      }
      next[queryKey] = target;
      if (kind == MemeFeedbackKind.correction &&
          aliasKey.isNotEmpty &&
          aliasKey != queryKey) {
        next[aliasKey] = _FeedbackEntry(
          correction: correctionValue,
          votes: {...?next[aliasKey]?.votes, candidate: MemeFeedbackKind.wrong},
        );
      }
      await _save(next);
      _entries = next;
    });
    // Keep later records serial even when one disk write fails. The failed
    // record is deliberately not reflected in memory.
    _commitTail = commit.catchError((_) {});
    return commit;
  }

  /// Prefers the inspected original URL. Preview URLs must not turn a saved
  /// thumbnail into the identity of a different original result.
  static String candidateKey(MemeAsset asset) {
    final original = RankingService.canonicalOriginalUrl(
      asset.originalUrl ?? '',
    );
    return original.isNotEmpty ? 'url:$original' : 'id:${asset.id}';
  }

  static Map<String, _FeedbackEntry> _copyEntries(
    Map<String, _FeedbackEntry> source,
  ) => source.map((key, value) => MapEntry(key, value.copy()));

  static String _normalizeQuery(String value) {
    final withoutTags = value.replaceAll(RegExp(r'(^|\s)#[^\s]+'), ' ');
    return RegExp(r'[\p{L}\p{N}]', unicode: true)
        .allMatches(withoutTags.toLowerCase())
        .map((match) => match.group(0)!)
        .join();
  }

  Future<void> _save(Map<String, _FeedbackEntry> entries) async {
    await _file.parent.create(recursive: true);
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'version': _version,
      'queries': entries.map((key, value) => MapEntry(key, value.toJson())),
    });
    final temporary = File(
      '${_file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(_file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class _FeedbackEntry {
  const _FeedbackEntry({this.correction, this.votes = const {}});

  final String? correction;
  final Map<String, MemeFeedbackKind> votes;

  _FeedbackEntry copy() => _FeedbackEntry(
    correction: correction,
    votes: Map<String, MemeFeedbackKind>.from(votes),
  );

  Map<String, Object?> toJson() => {
    if (correction != null) 'correction': correction,
    'votes': votes.map((key, value) => MapEntry(key, value.name)),
  };

  static _FeedbackEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final votes = <String, MemeFeedbackKind>{};
    final rawVotes = raw['votes'];
    if (rawVotes is Map) {
      for (final vote in rawVotes.entries) {
        final kind = switch (vote.value) {
          'helpful' => MemeFeedbackKind.helpful,
          'wrong' => MemeFeedbackKind.wrong,
          _ => null,
        };
        if (kind != null) votes[vote.key.toString()] = kind;
      }
    }
    final correction = raw['correction'];
    return _FeedbackEntry(
      correction: correction is String && correction.trim().isNotEmpty
          ? correction
          : null,
      votes: votes,
    );
  }
}
