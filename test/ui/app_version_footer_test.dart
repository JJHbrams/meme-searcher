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
                  return pending.future;
                }
                onProgress(const UpdateProgress(UpdatePhase.restart));
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
}
