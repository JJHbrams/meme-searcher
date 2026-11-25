import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/app_update.dart';
import 'package:meme_searcher/platform/media_actions.dart';
import 'package:meme_searcher/ui/widgets/app_version_footer.dart';

void main() {
  testWidgets(
    'manual update check can retry and offers the newer Windows release',
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
      expect(find.text('Windows ZIP 다운로드'), findsOneWidget);
      await tester.tap(find.text('업데이트 확인'));
      await tester.pumpAndSettle();
      expect(find.text('사용 가능한 새 버전이 없어요.'), findsOneWidget);
      expect(find.text('Windows ZIP 다운로드'), findsNothing);
    },
  );
}
