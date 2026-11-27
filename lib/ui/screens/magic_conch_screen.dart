import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

const _conchViewType = 'dev.memesearcher.meme_searcher/magic_conch';

class MagicConchScreen extends StatefulWidget {
  const MagicConchScreen({super.key});

  @override
  State<MagicConchScreen> createState() => _MagicConchScreenState();
}

class _MagicConchScreenState extends State<MagicConchScreen> {
  final _windowsController = Platform.isAndroid ? null : WebviewController();
  MethodChannel? _androidChannel;
  StreamSubscription<LoadingState>? _loading;
  StreamSubscription<dynamic>? _webMessages;
  late final AppLifecycleListener _lifecycle;
  late final _ready = _openWindows();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (_) => unawaited(_syncAudioFocus()),
    );
  }

  void _onAndroidViewCreated(int id) {
    _androidChannel = MethodChannel('$_conchViewType/$id');
    unawaited(_syncAudioFocus());
  }

  Future<void> _syncAudioFocus() async {
    if (!mounted) return;
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final android = _androidChannel;
    final windows = _windowsController;
    try {
      if (android != null) {
        await android.invokeMethod<void>('setForeground', foreground);
      } else if (windows != null && windows.value.isInitialized) {
        await windows.executeScript(
          'window.__memeConchAudio?.setForeground($foreground)',
        );
      }
    } on MissingPluginException {
      // The platform view may have been removed during a lifecycle transition.
    } on PlatformException {
      // A navigation can replace the document while the script is in flight.
    }
  }

  Future<bool> _openWindows() async {
    final controller = _windowsController!;
    if (await WebviewController.getWebViewVersion() == null) return false;
    if (!mounted) return false;
    final directory = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'magical_conch',
    );
    if (!await File(p.join(directory, 'index.html')).exists()) {
      throw StateError('Missing bundled Magical Conch app');
    }
    if (!mounted) return false;
    await controller.initialize();
    if (!mounted) return false;
    _webMessages = controller.webMessage.listen((message) {
      if (message is Map && message['type'] == 'openWillowJingle') {
        unawaited(
          launchUrl(
            Uri.parse('https://www.youtube.com/watch?v=f5v2xcBNNic'),
            mode: LaunchMode.externalApplication,
          ),
        );
      }
    });
    _loading = controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted) {
        unawaited(_syncAudioFocus());
      }
    });
    await controller.addVirtualHostNameMapping(
      'conch.example',
      directory,
      WebviewHostResourceAccessKind.deny,
    );
    if (!mounted) return false;
    await controller.loadUrl('https://conch.example/index.html');
    return true;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_loading?.cancel());
    unawaited(_webMessages?.cancel());
    unawaited(_windowsController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Platform.isAndroid
      ? AndroidView(
          viewType: _conchViewType,
          onPlatformViewCreated: _onAndroidViewCreated,
        )
      : _buildWindowsWebView();

  Widget _buildWindowsWebView() => FutureBuilder<bool>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: '소라고동 여는 중'),
        );
      }
      if (snapshot.data == true) {
        return Webview(
          _windowsController!,
          permissionRequested: (_, _, _) => WebviewPermissionDecision.deny,
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                snapshot.hasError
                    ? '소라고동을 열지 못했어요. 배포 ZIP 전체를 풀었는지 확인한 뒤 다시 열어 주세요.'
                    : '소라고동을 열려면 Microsoft Edge WebView2 런타임이 필요해요.',
                textAlign: TextAlign.center,
              ),
              if (!snapshot.hasError)
                TextButton(
                  onPressed: () async {
                    final url = Uri.https(
                      'developer.microsoft.com',
                      '/microsoft-edge/webview2/',
                    );
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                  child: const Text('WebView2 다운로드'),
                ),
            ],
          ),
        ),
      );
    },
  );
}
