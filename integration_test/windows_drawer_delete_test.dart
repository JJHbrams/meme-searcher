import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/catalog.dart';
import 'package:meme_searcher/core/device_app_services.dart';
import 'package:meme_searcher/core/local_library_store.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/serpapi_account.dart';
import 'package:meme_searcher/platform/media_actions.dart';
import 'package:meme_searcher/ui/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preview and mixed selection delete from a real drawer', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('meme-delete-ui-');
    addTearDown(() => root.delete(recursive: true));
    FlutterSecureStorage.setMockInitialValues({'serpapi_setup_deferred': '1'});
    Future<LocalLibraryStore> openStore() => LocalLibraryStore.open(
      directory: root,
      bundledDigests: MemeCatalog.bundledDigests,
    );
    final store = await openStore();
    final saved = await store.keepMedia(_png('보관한 테스트 짤', 75));
    final cached = await store.cacheMedia(
      _png('임시 테스트 짤', 150),
      previewOnly: false,
    );
    final savedInPreview = await store.cacheMedia(
      _png('열어서 저장', 175),
      previewOnly: false,
    );
    final copiedInPreview = await store.cacheMedia(
      _png('열어서 복사', 200),
      previewOnly: false,
    );
    final app = DeviceAppServices(
      store: store,
      fetchQuota: (_) async => const SerpApiQuota(),
    );
    await app.initialize();
    final seed = (await app.library()).firstWhere((a) => a.origin == 'seed');
    await app.markRecent(seed.id, asset: seed);
    await tester.pumpWidget(
      MemeSearcherApp(services: app, actions: _TestClipboard()),
    );

    Future<void> tap(Finder target) async {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      bool ready() {
        final widget = target.evaluate().firstOrNull?.widget;
        return widget != null &&
            (widget is! ButtonStyleButton || widget.enabled);
      }

      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(ready(), isTrue, reason: 'Waiting for enabled target $target');
      await Scrollable.ensureVisible(
        target.first.evaluate().single,
        alignment: .5,
      );
      await tester.pump();
      expect(target.hitTestable(), findsWidgets);
      await tester.tap(target.hitTestable().first);
      await tester.pump(const Duration(milliseconds: 350));
    }

    Finder key(String name) => find.byKey(ValueKey(name));
    await tap(find.text(seed.title));
    await tap(key('preview-delete'));
    await tap(key('confirm-delete'));
    await tap(key('nav-all'));
    for (final (item, action, feedback) in [
      (savedInPreview, '내 짤에 저장', '내 짤에 저장했어요.'),
      (copiedInPreview, '복사', '클립보드에 복사했어요.'),
    ]) {
      await tap(find.text(item.asset.title));
      await tap(
        find.ancestor(
          of: find.text(action),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (find.text(feedback).evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(
        find.text(feedback),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data)
            .join(' | '),
      );
      await tap(key('preview-delete'));
      await tap(key('confirm-delete'));
      final closeDeadline = DateTime.now().add(const Duration(seconds: 8));
      while (find.byType(Dialog).evaluate().isNotEmpty &&
          DateTime.now().isBefore(closeDeadline)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Dialog), findsNothing);
      expect(
        (await app.library()).map((asset) => asset.title),
        isNot(contains(item.asset.title)),
      );
    }
    await tap(key('nav-all'));
    await tap(key('select-delete'));
    await tap(find.text(cached.asset.title));
    await tap(find.text(saved.title));
    await tap(key('delete-selected'));
    await tap(key('confirm-delete'));
    await tester.pumpWidget(const SizedBox.shrink());

    final restarted = DeviceAppServices(store: await openStore());
    await restarted.initialize();
    final remaining = (await restarted.library()).map((a) => a.id).toSet();
    expect(remaining, isNot(contains(seed.id)));
    expect(remaining, isNot(contains(saved.id)));
    expect(remaining, contains(MemeCatalog.seedAssets.last.id));
    expect(remaining, hasLength(MemeCatalog.seedAssets.length - 1));
    expect(await restarted.cachedLibrary(), isEmpty);
    expect(await restarted.library(recentOnly: true), isEmpty);
    expect(await File(saved.filePath!).exists(), isFalse);
    expect(await File(cached.path).exists(), isFalse);
  }, skip: !Platform.isWindows);
}

class _TestClipboard extends MediaActions {
  @override
  Future<MediaActionResult> copy(MediaFile file) async {
    if (!await File(file.path).exists()) {
      throw StateError('Missing test clipboard file');
    }
    return const MediaActionResult.success();
  }
}

MediaFile _png(String title, int red) {
  final pixel = image.Image(width: 1, height: 1)..setPixelRgb(0, 0, red, 0, 0);
  return MediaFile(
    path: '',
    bytes: image.encodePng(pixel),
    asset: MemeAsset(id: title, title: title, origin: 'web', format: 'PNG'),
  );
}
