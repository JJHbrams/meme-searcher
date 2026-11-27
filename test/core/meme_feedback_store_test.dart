import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/meme_feedback_store.dart';
import 'package:meme_searcher/core/models.dart';

void main() {
  late Directory drawer;

  const first = MemeAsset(
    id: 'first',
    title: 'generated title is not used',
    origin: 'web',
    originalUrl: 'https://example.test/a.gif#one',
    previewUrl: 'https://example.test/thumb.jpg',
  );
  const second = MemeAsset(
    id: 'second',
    title: 'other',
    origin: 'web',
    originalUrl: 'https://example.test/b.gif',
  );
  const third = MemeAsset(id: 'third', title: 'local', origin: 'library');

  setUp(() async {
    drawer = await Directory.systemTemp.createTemp('meme-feedback-store-test-');
  });
  tearDown(() => drawer.delete(recursive: true));

  test(
    'persists punctuation-insensitive votes and reranks only that query',
    () async {
      final store = await MemeFeedbackStore.open(drawer);
      await store.record(
        query: 'Wapa~ #Friends',
        asset: second,
        kind: MemeFeedbackKind.helpful,
      );
      await store.record(
        query: 'wapa',
        asset: first,
        kind: MemeFeedbackKind.wrong,
      );

      expect(store.rerank('wapa!', [first, second, third]), [
        second,
        third,
        first,
      ]);
      expect(store.rerank('different', [first, second, third]), [
        first,
        second,
        third,
      ]);

      final reopened = await MemeFeedbackStore.open(drawer);
      expect(reopened.rerank('WAPA…', [first, second, third]), [
        second,
        third,
        first,
      ]);
    },
  );

  test(
    'correction scopes a rejected candidate and optional alias together',
    () async {
      final store = await MemeFeedbackStore.open(drawer);
      await store.record(
        query: 'wapa~',
        asset: first,
        kind: MemeFeedbackKind.correction,
        correction: 'whoopah',
        alias: 'wah-pah',
      );

      expect(store.correctedQueryFor('wapa'), 'whoopah');
      expect(store.correctedQueryFor('wah pah'), 'whoopah');
      expect(store.rerank('wah-pah', [first, second]), [second, first]);
    },
  );

  test(
    'candidate key uses the original URL or stable asset id, never a preview',
    () {
      expect(
        MemeFeedbackStore.candidateKey(first),
        'url:https://example.test/a.gif',
      );
      expect(MemeFeedbackStore.candidateKey(third), 'id:third');
    },
  );

  test('malformed feedback file is not rewritten while opening', () async {
    final file = File(
      '${drawer.path}${Platform.pathSeparator}meme-feedback-v1.json',
    );
    await file.writeAsString('{not json');
    final store = await MemeFeedbackStore.open(drawer);

    expect(store.correctedQueryFor('anything'), isNull);
    expect(await file.readAsString(), '{not json');
  });

  test(
    'writes a versioned store and later correction replaces the lookup',
    () async {
      final store = await MemeFeedbackStore.open(drawer);
      await store.record(
        query: 'wapa',
        asset: first,
        kind: MemeFeedbackKind.correction,
        correction: 'whoopah',
      );
      await store.record(
        query: 'wapa',
        asset: first,
        kind: MemeFeedbackKind.correction,
        correction: 'whoopah chandler',
      );

      final file = File(
        '${drawer.path}${Platform.pathSeparator}meme-feedback-v1.json',
      );
      expect(jsonDecode(await file.readAsString())['version'], 1);
      expect(store.correctedQueryFor('wapa~'), 'whoopah chandler');
    },
  );
}
