import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../../platform/media_actions.dart';
import '../app_theme.dart';
import 'serpapi_settings_dialog.dart';
import '../widgets/source_badge.dart';
import '../widgets/tag_chip.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.services,
    required this.actions,
    super.key,
  });

  final AppServices services;
  final MediaActions actions;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _tagController = TextEditingController();
  final _searchFocus = FocusNode();
  final List<String> _tags = [];
  List<MemeAsset> _assets = [];
  SearchScope _scope = SearchScope.library;
  MediaFilter _filter = MediaFilter.all;
  bool _similar = false;
  bool _loading = true;
  bool _hasSearched = false;
  bool _openingSettings = false;
  String? _error;
  int _searchSerial = 0;
  _NavMode _navMode = _NavMode.all;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tagController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await widget.services.initialize();
      await _search(initial: true);
      if (mounted) await _openSettings(firstRun: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '라이브러리를 불러오지 못했어요.';
          _loading = false;
        });
      }
    }
  }

  void _parseInlineTags() {
    final words = <String>[];
    for (final token in _searchController.text.trim().split(RegExp(r'\s+'))) {
      if (token.startsWith('#') && token.length > 1) {
        _addTag(token.substring(1));
      } else if (token.isNotEmpty) {
        words.add(token);
      }
    }
    _searchController.value = TextEditingValue(
      text: words.join(' '),
      selection: TextSelection.collapsed(offset: words.join(' ').length),
    );
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceFirst(RegExp(r'^#'), '');
    if (tag.isNotEmpty && !_tags.contains(tag)) setState(() => _tags.add(tag));
  }

  Future<void> _search({bool initial = false}) async {
    if (!initial) _parseInlineTags();
    final serial = ++_searchSerial;
    final request = SearchRequest(
      query: _searchController.text.trim(),
      scope: _scope,
      filter: _filter,
      similar: _scope == SearchScope.web ? false : _similar,
      tags: List.unmodifiable(_tags),
      favoritesOnly: _navMode == _NavMode.favorites,
      recentOnly: _navMode == _NavMode.recent,
    );
    if (!initial &&
        _scope != SearchScope.library &&
        request.fullQuery.isEmpty) {
      _show('웹 검색어를 입력해 주세요.');
      _searchFocus.requestFocus();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (!initial) _hasSearched = true;
    });
    try {
      final response = await widget.services.search(request);
      if (!mounted || serial != _searchSerial) return;
      setState(() {
        _assets = response.assets;
        _error = response.error;
      });
    } catch (_) {
      if (mounted && serial == _searchSerial) {
        setState(() => _error = '검색을 완료하지 못했어요.');
      }
    } finally {
      if (mounted && serial == _searchSerial) setState(() => _loading = false);
    }
  }

  Future<void> _changeNav(_NavMode value) async {
    setState(() => _navMode = value);
    await _search();
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  String _source(MemeAsset asset) {
    final labels = <String>[];
    if (!asset.isWeb) labels.add('내 짤');
    for (final engine in asset.engines) {
      final label = engine.contains('Google')
          ? 'Google'
          : engine.contains('Naver')
          ? 'Naver'
          : engine;
      if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
    }
    return labels.join(' · ');
  }

  static String _mediaInfo(MemeAsset asset) {
    final format = asset.displayFormat;
    final size = asset.width != null && asset.height != null
        ? '${asset.width}×${asset.height}'
        : '크기 미확인';
    final movement = asset.motionVerified
        ? ' · 움직임 확인'
        : asset.isGif && (asset.frames ?? 0) > 1
        ? ' · ${asset.frames}프레임'
        : asset.isGif && asset.frames == 1
        ? ' · 정지(1프레임)'
        : '';
    return [?format, '$size$movement'].join(' · ');
  }

  Future<void> _openAsset(MemeAsset asset) async {
    try {
      await widget.services.markRecent(asset.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _PreviewDialog(
          asset: asset,
          services: widget.services,
          actions: widget.actions,
          source: _source(asset),
          onInspected: (inspected) {
            final index = _assets.indexWhere((a) => a.id == asset.id);
            if (mounted && index >= 0) {
              setState(() => _assets = [..._assets]..[index] = inspected);
            }
          },
          onSaved: () async {
            await _search();
          },
        ),
      );
    } catch (_) {
      _show('미리보기를 열지 못했어요.');
    }
  }

  Future<void> _openSettings({bool firstRun = false}) async {
    if (_openingSettings) return;
    _openingSettings = true;
    try {
      final settings = await widget.services.settings();
      if (!mounted ||
          (firstRun &&
              (settings.serpApiConfigured || settings.serpApiSetupDeferred))) {
        return;
      }
      final connected = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SerpApiSettingsDialog(
          services: widget.services,
          settings: settings,
          firstRun: firstRun,
        ),
      );
      if (connected == true && mounted) {
        _show('SerpApi 키를 확인하고 저장했어요. 웹 또는 모두에서 검색해 보세요.');
      }
    } catch (_) {
      if (mounted) _show('검색 설정을 읽지 못했어요. 설정에서 다시 시도해 주세요.');
    } finally {
      _openingSettings = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              _SideRail(
                mode: _navMode,
                onChanged: _changeNav,
                onSettings: _openSettings,
              ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 46 : 20,
                      34,
                      wide ? 46 : 20,
                      80,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _Header(
                          assetCount: _assets.length,
                          onSettings: _openSettings,
                          compact: !wide,
                        ),
                        const SizedBox(height: 30),
                        _searchBox(),
                        const SizedBox(height: 12),
                        _scopeChoice(),
                        const SizedBox(height: 8),
                        _similarChoice(),
                        const SizedBox(height: 12),
                        _formatChoice(),
                        if (!_hasSearched) ...[
                          const SizedBox(height: 22),
                          _examples(),
                        ],
                        if (_hasSearched) ...[
                          const SizedBox(height: 22),
                          _tagFilter(),
                        ],
                        const SizedBox(height: 28),
                        _resultHeading(),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          _InlineMessage(message: _error!, error: true),
                        ],
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  _resultsGrid(wide),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _navMode.index,
              onDestinationSelected: (index) =>
                  _changeNav(_NavMode.values[index]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: '전체',
                ),
                NavigationDestination(
                  icon: Icon(Icons.star_border),
                  label: '즐겨찾기',
                ),
                NavigationDestination(icon: Icon(Icons.history), label: '최근'),
              ],
            ),
    );
  }

  Widget _searchBox() => Form(
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            style: const TextStyle(
              color: MemeTheme.accentInk,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, color: MemeTheme.accentInk),
              hintText: '밈 키워드, 문구, 캐릭터를 입력하세요',
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _loading ? null : _search,
          style: FilledButton.styleFrom(
            backgroundColor: MemeTheme.accent,
            foregroundColor: MemeTheme.accentInk,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
          ),
          child: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('검색'),
        ),
      ],
    ),
  );

  Widget _scopeChoice() => SegmentedButton<SearchScope>(
    segments: const [
      ButtonSegment(value: SearchScope.library, label: Text('내 짤')),
      ButtonSegment(value: SearchScope.web, label: Text('웹')),
      ButtonSegment(value: SearchScope.all, label: Text('모두')),
    ],
    selected: {_scope},
    onSelectionChanged: (value) => setState(() {
      _scope = value.first;
      if (_scope == SearchScope.web) _similar = false;
    }),
    showSelectedIcon: false,
  );

  Widget _similarChoice() => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: _similar,
    onChanged: _scope == SearchScope.web
        ? null
        : (value) => setState(() => _similar = value ?? false),
    controlAffinity: ListTileControlAffinity.leading,
    title: const Text('비슷한 문구 포함', style: TextStyle(fontSize: 13)),
    subtitle: const Text('등록된 별칭·변형 문구 포함', style: TextStyle(fontSize: 11)),
  );

  Widget _formatChoice() => Wrap(
    spacing: 8,
    children:
        [
              (MediaFilter.all, '전체'),
              (MediaFilter.gif, 'GIF'),
              (MediaFilter.staticImage, '정지'),
            ]
            .map(
              (item) => ChoiceChip(
                label: Text(item.$2),
                selected: _filter == item.$1,
                onSelected: (_) => setState(() => _filter = item.$1),
              ),
            )
            .toList(),
  );

  Widget _examples() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '검색 예시',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ['approved!', '좋다 지금 간다 기다려라', '틀깨기!']
            .map(
              (value) => ActionChip(
                label: Text(value),
                onPressed: () {
                  _searchController.text = value;
                  _searchFocus.requestFocus();
                },
              ),
            )
            .toList(),
      ),
    ],
  );

  Widget _tagFilter() => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: MemeTheme.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('태그 필터', style: TextStyle(fontWeight: FontWeight.w800)),
          ..._tags.map(
            (tag) => TagChip(
              label: tag,
              onDelete: () => setState(() => _tags.remove(tag)),
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _tagController,
              onSubmitted: (value) {
                _addTag(value);
                _tagController.clear();
                _search();
              },
              decoration: const InputDecoration(
                isDense: true,
                prefixText: '#',
                hintText: '태그 추가',
                fillColor: Colors.transparent,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              _addTag(_tagController.text);
              _tagController.clear();
              _search();
            },
            child: const Text('필터 검색'),
          ),
          TextButton(
            onPressed: _tags.isEmpty ? null : () => setState(_tags.clear),
            child: const Text('지우기'),
          ),
        ],
      ),
    ),
  );

  Widget _resultHeading() => Row(
    children: [
      const Text(
        '검색 결과',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      const SizedBox(width: 8),
      Text(
        '${_assets.length}개',
        style: const TextStyle(color: MemeTheme.muted, fontSize: 13),
      ),
    ],
  );

  Widget _resultsGrid(bool wide) {
    if (_loading && _assets.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_assets.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text('일치하는 짤이 없어요', style: TextStyle(color: MemeTheme.muted)),
        ),
      );
    }
    final count = wide ? 5 : 2;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(wide ? 46 : 20, 0, wide ? 46 : 20, 90),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: .74,
        ),
        itemCount: _assets.length,
        itemBuilder: (context, index) {
          final asset = _assets[index];
          Widget card(MemeAsset item, {bool probing = false}) => _MemeCard(
            asset: item,
            source: _source(item),
            mediaInfo: _mediaInfo(item),
            probing: probing,
            onTap: () => _openAsset(item),
          );
          if (!asset.isWeb || asset.displayFormat != null) return card(asset);
          return FutureBuilder<String?>(
            key: ValueKey(asset.originalUrl ?? asset.id),
            future: widget.services.probeWebFormat(asset),
            builder: (_, snapshot) => card(
              snapshot.hasData
                  ? asset.copyWith(formatHint: snapshot.data)
                  : asset,
              probing: snapshot.connectionState == ConnectionState.waiting,
            ),
          );
        },
      ),
    );
  }
}

enum _NavMode { all, favorites, recent }

class _Header extends StatelessWidget {
  const _Header({
    required this.assetCount,
    required this.onSettings,
    required this.compact,
  });

  final int assetCount;
  final VoidCallback onSettings;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LIVE MEME SEARCH',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.8,
                color: MemeTheme.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '밈 찾기',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
          ],
        ),
      ),
      Text(
        '$assetCount개 밈',
        style: const TextStyle(color: MemeTheme.muted, fontSize: 12),
      ),
      if (compact)
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
    ],
  );
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.mode,
    required this.onChanged,
    required this.onSettings,
  });

  final _NavMode mode;
  final ValueChanged<_NavMode> onChanged;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Container(
    width: 196,
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: MemeTheme.border)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 12, 8, 30),
            child: Row(
              children: [
                Image(
                  image: AssetImage('assets/app-icon.png'),
                  width: 40,
                  height: 40,
                  excludeFromSemantics: true,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Meme\nSearcher',
                    style: TextStyle(fontWeight: FontWeight.w800, height: 1),
                  ),
                ),
              ],
            ),
          ),
          _railButton(Icons.grid_view_rounded, '전체', _NavMode.all),
          _railButton(Icons.star_border, '즐겨찾기', _NavMode.favorites),
          _railButton(Icons.history, '최근', _NavMode.recent),
          const Spacer(),
          TextButton.icon(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('설정'),
          ),
        ],
      ),
    ),
  );

  Widget _railButton(IconData icon, String label, _NavMode value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: mode == value
            ? MemeTheme.surfaceRaised
            : Colors.transparent,
        foregroundColor: MemeTheme.text,
        alignment: Alignment.centerLeft,
      ),
      onPressed: () => onChanged(value),
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

class _MemeCard extends StatelessWidget {
  const _MemeCard({
    required this.asset,
    required this.source,
    required this.mediaInfo,
    required this.probing,
    required this.onTap,
  });

  final MemeAsset asset;
  final String source;
  final String mediaInfo;
  final bool probing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: MemeTheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: MemeTheme.border),
    ),
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _AssetImage(asset: asset, fit: BoxFit.cover),
                Positioned(left: 7, top: 7, child: SourceBadge(label: source)),
                Positioned(
                  right: 7,
                  top: 7,
                  child: SourceBadge(
                    label: asset.motionVerified
                        ? 'GIF · 움직임 확인'
                        : asset.displayFormat ??
                              (probing ? '형식 확인 중' : '원본 확인 필요'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  asset.variant ?? asset.familyName ?? '웹 검색 후보',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MemeTheme.muted, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  mediaInfo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MemeTheme.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AssetImage extends StatelessWidget {
  const _AssetImage({required this.asset, this.fit = BoxFit.contain});

  final MemeAsset asset;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final filePath = asset.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      return Image.file(
        File(filePath),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    final bundled = asset.bundledAssetPath;
    if (bundled != null && bundled.isNotEmpty) {
      return Image.asset(
        bundled,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    final preview = asset.previewUrl;
    if (preview != null && preview.startsWith(RegExp(r'https?://'))) {
      return Image.network(
        preview,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => const ColoredBox(
    color: MemeTheme.surfaceRaised,
    child: Center(
      child: Icon(Icons.image_not_supported_outlined, color: MemeTheme.muted),
    ),
  );
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({
    required this.asset,
    required this.services,
    required this.actions,
    required this.source,
    required this.onInspected,
    required this.onSaved,
  });

  final MemeAsset asset;
  final AppServices services;
  final MediaActions actions;
  final String source;
  final ValueChanged<MemeAsset> onInspected;
  final Future<void> Function() onSaved;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  MediaFile? _media;
  String? _error;
  bool _busy = true;
  bool _previewOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _previewOnly = false;
      _media = null;
    });
    try {
      final media = await widget.services.loadMedia(widget.asset);
      if (!mounted) return;
      setState(() => _media = media);
      widget.onInspected(media.asset);
    } catch (_) {
      if (!mounted) return;
      try {
        final preview = await widget.services.loadPreviewMedia(widget.asset);
        if (mounted) {
          setState(() {
            _media = preview;
            _previewOnly = true;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _error = '이미지를 불러오지 못했어요. 출처에서 원본을 확인하거나 다시 시도해 주세요.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(
    Future<MediaActionResult> Function(MediaFile) action,
    String success,
  ) async {
    final media = _media;
    if (media == null) return;
    try {
      final result = await action(media);
      if (!mounted || result.cancelled) return;
      if (result.completed) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } on MediaActionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _saveToLibrary() async {
    final media = _media;
    if (media == null || !widget.asset.isWeb) {
      return;
    }
    try {
      await widget.services.saveToLibrary(media, title: widget.asset.title);
      await widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('내 짤에 저장했어요.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('저장하지 못했어요.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
          _copy(),
    },
    child: Focus(autofocus: true, child: _dialog(context)),
  );

  void _copy() {
    if (_media != null) {
      _run(
        widget.actions.copy,
        _previewOnly ? '미리보기 이미지를 복사했어요.' : '클립보드에 복사했어요.',
      );
    }
  }

  Widget _dialog(BuildContext context) {
    final displayed = _media?.asset ?? widget.asset;
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: MemeTheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: '미리보기 닫기',
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .48,
                  ),
                  child: AspectRatio(
                    aspectRatio:
                        (displayed.width != null &&
                            displayed.height != null &&
                            displayed.width! > 0 &&
                            displayed.height! > 0)
                        ? displayed.width! / displayed.height!
                        : 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ColoredBox(
                        color: MemeTheme.cream,
                        child: _busy
                            ? const Center(child: CircularProgressIndicator())
                            : _error != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : Image.memory(_media!.bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.source,
                  style: const TextStyle(
                    color: MemeTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.asset.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  _SearchScreenState._mediaInfo(displayed),
                  style: const TextStyle(color: MemeTheme.muted),
                ),
                if (_previewOnly)
                  const Text(
                    '원본을 열 수 없어 검색 엔진의 미리보기를 표시했어요. 복사하면 이 크기로 붙여넣어요.',
                  ),
                if (_previewOnly || _error != null)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('원본 다시 시도'),
                  ),
                if (widget.asset.matchReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.asset.matchReason!,
                    style: const TextStyle(
                      color: MemeTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _media == null ? null : _copy,
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(_previewOnly ? '미리보기 이미지 복사' : '복사'),
                    ),
                    if (Platform.isWindows && !_previewOnly && !displayed.isGif)
                      OutlinedButton.icon(
                        onPressed: _media == null
                            ? null
                            : () => _run(
                                widget.actions.copyFile,
                                '원본 파일을 복사했어요.',
                              ),
                        icon: const Icon(Icons.file_copy_outlined),
                        label: const Text('파일로 복사'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _media == null || _previewOnly
                          ? null
                          : () => _run(widget.actions.save, '원본을 저장했어요.'),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('원본 저장'),
                    ),
                    if (!Platform.isWindows)
                      OutlinedButton.icon(
                        onPressed: _media == null || _previewOnly
                            ? null
                            : () => _run(widget.actions.share, '공유 화면을 열었어요.'),
                        icon: const Icon(Icons.ios_share_outlined),
                        label: const Text('공유'),
                      ),
                    if (widget.asset.isWeb)
                      OutlinedButton.icon(
                        onPressed: _media == null || _previewOnly
                            ? null
                            : _saveToLibrary,
                        icon: const Icon(Icons.add_to_photos_outlined),
                        label: const Text('내 짤에 저장'),
                      ),
                    if (widget.asset.sourceUrl != null ||
                        widget.asset.originalUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            widget.asset.sourceUrl ?? widget.asset.originalUrl!,
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('출처'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Esc 닫기 · Ctrl + C 복사',
                  style: TextStyle(color: MemeTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: error ? const Color(0xff332925) : MemeTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(message, style: const TextStyle(fontSize: 12)),
    ),
  );
}
