import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/app_update.dart';
import 'package:meme_searcher/core/windows_update_installer.dart';
import 'package:meme_searcher/platform/media_actions.dart';
import 'package:meme_searcher/ui/widgets/app_version_footer.dart';

void main() {
  testWidgets(
    'manual update check can retry and offers the release page when install is unavailable',
    (tester) async {
      const channel = MethodChannel(MediaActions.channelName);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => '1.4.0.28');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var calls = 0;
      final pending = Completer<WindowsRelease?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppVersionFooter(
              showUpdateCheck: true,
              check: (version) async {
                expect(version, '1.4.0.28');
                calls++;
                if (calls == 1) return pending.future;
                if (calls == 2) {
                  return const WindowsRelease('v1.5.0.30', hasZip: true);
                }
                return null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('업데이트 확인'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '확인 중…'))
            .onPressed,
        isNull,
      );
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('업데이트를 확인하지 못했어요'), findsOneWidget);
      await tester.tap(find.text('업데이트 확인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('새 버전 v1.5.0.30'), findsOneWidget);
      expect(find.text('릴리즈 페이지 열기'), findsOneWidget);
      await tester.tap(find.text('업데이트 확인'));
      await tester.pumpAndSettle();
      expect(find.text('사용 가능한 새 버전이 없어요.'), findsOneWidget);
      expect(find.text('릴리즈 페이지 열기'), findsNothing);
    },
  );

  testWidgets(
    'install shows progress, prevents duplicate starts, and retries',
    (tester) async {
      const channel = MethodChannel(MediaActions.channelName);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => '1.4.0.28');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppVersionFooter(
              showUpdateCheck: true,
              check: (_) async => const WindowsRelease(
                'v1.5.0.30',
                hasZip: true,
                zipSha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              ),
              install: (release, {required onProgress}) async {
                calls++;
                if (calls == 1) {
                  onProgress(const UpdateProgress(UpdatePhase.download, .5));
                  await pending.future;
                }
                onProgress(const UpdateProgress(UpdatePhase.restart));
                return AppUpdateHandoff.windowsRestart;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('업데이트 확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('업데이트 설치'));
      await tester.pump();
      expect(find.bySemanticsLabel('업데이트를 다운로드하는 중이에요. 50%'), findsOneWidget);
      await tester.tap(find.text('업데이트 적용 중…'));
      await tester.tap(find.text('업데이트 확인'));
      await tester.pump();
      expect(calls, 1);
      expect(find.bySemanticsLabel('업데이트를 다운로드하는 중이에요. 50%'), findsOneWidget);
      pending.completeError(const AppUpdateException('다운로드 파일을 확인할 수 없어요.'));
      await tester.pumpAndSettle();
      expect(find.text('다운로드 파일을 확인할 수 없어요.'), findsOneWidget);
      expect(find.text('릴리즈 페이지 열기'), findsOneWidget);
      await tester.tap(find.text('업데이트 설치'));
      await tester.pump();
      expect(calls, 2);
      expect(find.text('업데이트를 적용하고 앱을 다시 시작해요.'), findsOneWidget);
    },
  );

  testWidgets('Android installation can resume after granting permission', (
    tester,
  ) async {
    const channel = MethodChannel(MediaActions.channelName);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => '1.8.1.91');
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final installing = <bool>[];
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppVersionFooter(
            showUpdateCheck: true,
            check: (_) async => const AndroidRelease(
              'v1.9.0.95',
              hasApk: true,
              apkSha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
            install: (_, {required onProgress}) async => ++attempts == 1
                ? AppUpdateHandoff.androidPermission
                : AppUpdateHandoff.androidInstaller,
            onInstallingChanged: installing.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('업데이트 확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('업데이트 설치'));
    await tester.pumpAndSettle();
    expect(find.textContaining('이 출처 허용'), findsOneWidget);
    await tester.tap(find.text('업데이트 설치'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Android 설치 화면'), findsOneWidget);
    expect(installing, [true, false, true, false]);
  });

  testWidgets('a newer Windows EXE already on disk only needs a restart', (
    tester,
  ) async {
    const channel = MethodChannel(MediaActions.channelName);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => '1.8.1.91');
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var checks = 0;
    var restarts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppVersionFooter(
            showUpdateCheck: true,
            readInstalledVersion: () async => '1.9.0.95',
            check: (_) async {
              checks++;
              return null;
            },
            restartInstalled: () async {
              restarts++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('업데이트 확인'));
    await tester.pumpAndSettle();
    expect(checks, 0);
    expect(find.textContaining('설치 폴더에 v1.9.0.95'), findsOneWidget);
    expect(find.text('업데이트 설치'), findsNothing);
    await tester.tap(find.text('앱 다시 시작'));
    await tester.pump();
    expect(restarts, 1);
  });
}
