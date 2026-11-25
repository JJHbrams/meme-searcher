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
  final _scroll = ScrollController();
  final List<String> _tags = [];
  List<MemeAsset> _assets = [];
  List<MemeAsset> _recentAssets = [];
  List<MemeAsset> _favoriteAssets = [];
  List<String> _recentQueries = [];
  SearchScope _scope = SearchScope.all;
  MediaFilter _filter = MediaFilter.all;
  bool _similar = false;
  bool _loading = true;
  bool _hasSearched = false;
  bool _showSearchOptions = false;
  bool _openingSettings = false;
  String? _error;
  int _searchSerial = 0;
  _NavMode _navMode = _NavMode.home;

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
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await widget.services.initialize();
      if (!mounted) return;
      if (_searchSerial == 0) await _loadPage();
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

  Future<void> _search() async {
    _parseInlineTags();
    final request = SearchRequest(
      query: _searchController.text.trim(),
      scope: _scope,
      filter: _filter,
      similar: _scope == SearchScope.web ? false : _similar,
      tags: List.unmodifiable(_tags),
    );
    if (_scope != SearchScope.library && request.fullQuery.isEmpty) {
      _show('웹 검색어를 입력해 주세요.');
      _searchFocus.requestFocus();
      return;
    }
    final serial = ++_searchSerial;
    _toTop();
    setState(() {
      _navMode = _NavMode.all;
      _loading = true;
      _error = null;
      _assets = [];
      _hasSearched = true;
    });
    try {
      if (request.fullQuery.isNotEmpty) {
        try {
          await widget.services.recordSearch(request.fullQuery);
        } catch (_) {
          // A history write failure should not prevent the search.
        }
        if (!mounted || serial != _searchSerial) return;
      }
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

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _changeNav(_NavMode value) {
    _toTop();
    _searchController.clear();
    _tagController.clear();
    _tags.clear();
    _filter = MediaFilter.all;
    _similar = false;
    _showSearchOptions = false;
    _navMode = value;
    _hasSearched = false;
    _assets = [];
    return _loadPage();
  }

  Future<void> _loadPage() async {
    final serial = ++_searchSerial;
    final mode = _navMode;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (mode == _NavMode.home) {
        final (recent, favorites, queries) = await (
          widget.services.library(recentOnly: true),
          widget.services.library(favoritesOnly: true),
          widget.services.recentSearches(),
        ).wait;
        if (!mounted || serial != _searchSerial) return;
        setState(() {
          _recentAssets = recent.take(5).toList();
          _favoriteAssets = favorites.take(5).toList();
          _recentQueries = queries.take(5).toList();
        });
      } else {
        final items = await widget.services.library(
          filter: _filter,
          favoritesOnly: mode == _NavMode.favorites,
          recentOnly: mode == _NavMode.recent,
        );
        if (!mounted || serial != _searchSerial) return;
        setState(() => _assets = items);
      }
    } catch (_) {
      if (mounted && serial == _searchSerial) {
        setState(() => _error = '목록을 불러오지 못했어요.');
      }
    } finally {
      if (mounted && serial == _searchSerial) setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
    final page = _searchSerial;
    try {
      await widget.services.markRecent(asset.id, asset: asset);
    } catch (_) {
      // Opening an image also works when its recent-use entry cannot be saved.
    }
    if (!mounted || page != _searchSerial) return;
    try {
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
              final updated = inspected.copyWith(
                favorite: _assets[index].favorite,
              );
              setState(() => _assets = [..._assets]..[index] = updated);
            }
          },
          onFavoriteChanged: (favorite) {
            final index = _assets.indexWhere((a) => a.id == asset.id);
            if (mounted && index >= 0) {
              setState(
                () =>
                    _assets = [..._assets]
                      ..[index] = _assets[index].copyWith(favorite: favorite),
              );
            }
          },
        ),
      );
      if (mounted && !_hasSearched) await _loadPage();
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
    final home = _navMode == _NavMode.home;
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final inset = wide ? 46.0 : 20.0;
                  // A 3:1 banner takes up at most 40% of the home viewport.
                  final homeWidth = (constraints.maxHeight * 1.2).clamp(
                    0.0,
                    1080.0,
                  );
                  final side = home
                      ? ((constraints.maxWidth - homeWidth) / 2).clamp(
                          inset,
                          double.infinity,
                        )
                      : inset;
                  return CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          side,
                          home ? 24 : 34,
                          side,
                          home ? 32 : 14,
                        ),
                        sliver: SliverList.list(
                          children: [
                            if (!home || !wide)
                              _Header(
                                title: _hasSearched ? '검색 결과' : _navMode.label,
                                assetCount: home || _loading
                                    ? null
                                    : _assets.length,
                                onSettings: _openSettings,
                                compact: !wide,
                              ),
                            if (home) ...[
                              if (!wide) const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 3,
                                  child: Image.asset(
                                    'docs/media/meme-drawer.jpg',
                                    fit: BoxFit.contain,
                                    semanticLabel: 'Meme Searcher 짤 서랍',
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(height: home ? 16 : 30),
                            _searchBox(),
                            const SizedBox(height: 12),
                            if (home) ...[
                              Row(
                                children: [
                                  Expanded(child: _scopeChoice()),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: _showSearchOptions
                                        ? '검색 옵션 접기'
                                        : '검색 옵션 열기',
                                    isSelected: _showSearchOptions,
                                    onPressed: () => setState(
                                      () => _showSearchOptions =
                                          !_showSearchOptions,
                                    ),
                                    icon: const Icon(Icons.tune),
                                  ),
                                ],
                              ),
                              if (_showSearchOptions) ...[
                                _similarChoice(),
                                _formatChoice(),
                              ],
                              const SizedBox(height: 20),
                              if (!_loading ||
                                  _recentAssets.isNotEmpty ||
                                  _recentQueries.isNotEmpty ||
                                  _favoriteAssets.isNotEmpty)
                                ..._homeSections()
                              else
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                            ] else ...[
                              _scopeChoice(),
                              if (_hasSearched) _similarChoice(),
                              const SizedBox(height: 12),
                              _formatChoice(),
                              if (_hasSearched) ...[
                                const SizedBox(height: 12),
                                _tagFilter(),
                              ],
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              _InlineMessage(message: _error!, error: true),
                            ],
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                      if (!home) _resultsGrid(wide),
                    ],
                  );
                },
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
                  key: ValueKey('nav-home'),
                  icon: Icon(Icons.home_outlined),
                  label: '홈',
                ),
                NavigationDestination(
                  key: ValueKey('nav-all'),
                  icon: Icon(Icons.grid_view_rounded),
                  label: '전체',
                ),
                NavigationDestination(
                  key: ValueKey('nav-favorites'),
                  icon: Icon(Icons.star_border),
                  label: '즐겨찾기',
                ),
                NavigationDestination(
                  key: ValueKey('nav-recent'),
                  icon: Icon(Icons.history),
                  label: '최근',
                ),
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
              (MediaFilter.staticImage, '이미지'),
            ]
            .map(
              (item) => ChoiceChip(
                label: Text(item.$2),
                selected: _filter == item.$1,
                onSelected: (_) {
                  setState(() => _filter = item.$1);
                  if (_navMode != _NavMode.home && !_hasSearched) _loadPage();
                },
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

  List<Widget> _homeSections() => [
    _homeAssets('최근 사용', _recentAssets, _NavMode.recent, '열어 본 짤이 여기에 모여요.'),
    const SizedBox(height: 22),
    const Text(
      '최근 검색',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 8),
    if (_recentQueries.isEmpty)
      const Text('아직 검색 기록이 없어요.', style: TextStyle(color: MemeTheme.muted))
    else
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final query in _recentQueries)
            ActionChip(
              avatar: const Icon(Icons.history, size: 16),
              label: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: () {
                _tags.clear();
                _searchController.text = query;
                _search();
              },
            ),
        ],
      ),
    const SizedBox(height: 22),
    _homeAssets(
      '즐겨찾기',
      _favoriteAssets,
      _NavMode.favorites,
      '미리보기에서 별을 누르면 이곳에 표시돼요.',
    ),
    if (_recentQueries.isEmpty) ...[const SizedBox(height: 24), _examples()],
  ];

  Widget _homeAssets(
    String title,
    List<MemeAsset> assets,
    _NavMode destination,
    String emptyMessage,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (assets.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _changeNav(destination),
              child: const Text('전체 보기'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (assets.isEmpty)
        Text(emptyMessage, style: const TextStyle(color: MemeTheme.muted))
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final columns = (constraints.maxWidth / 140).floor().clamp(1, 5);
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final asset in assets)
                  SizedBox(
                    width: width,
                    child: Material(
                      color: MemeTheme.surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: MemeTheme.border),
                      ),
                      child: InkWell(
                        onTap: () => _openAsset(asset),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 2.05,
                              child: _AssetImage(
                                asset: asset,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                asset.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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
          child: Text('표시할 짤이 없어요', style: TextStyle(color: MemeTheme.muted)),
        ),
      );
    }
    final inset = wide ? 46.0 : 20.0;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, 90),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) => SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ((constraints.crossAxisExtent + 12) / 162)
                .floor()
                .clamp(1, 5),
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
      ),
    );
  }
}

enum _NavMode {
  home('홈'),
  all('전체'),
  favorites('즐겨찾기'),
  recent('최근 사용');

  const _NavMode(this.label);
  final String label;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.assetCount,
    required this.onSettings,
    required this.compact,
  });

  final String title;
  final int? assetCount;
  final VoidCallback onSettings;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
      ),
      if (assetCount != null)
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
          _railButton(Icons.home_outlined, '홈', _NavMode.home),
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
      key: ValueKey('nav-${value.name}'),
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
    required this.onFavoriteChanged,
  });

  final MemeAsset asset;
  final AppServices services;
  final MediaActions actions;
  final String source;
  final ValueChanged<MemeAsset> onInspected;
  final ValueChanged<bool> onFavoriteChanged;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  MediaFile? _media;
  String? _error;
  bool _busy = true;
  bool _previewOnly = false;
  String? _feedback;
  bool _feedbackIsError = false;
  bool _changingFavorite = false;
  late bool _favorite = widget.asset.favorite;

  void _notify(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = error;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_changingFavorite) return;
    setState(() => _changingFavorite = true);
    try {
      final asset = _previewOnly
          ? widget.asset
          : (_media?.asset ?? widget.asset);
      final updated = await widget.services.toggleFavorite(
        widget.asset.id,
        asset: asset,
      );
      if (!mounted) return;
      _favorite = updated.favorite;
      widget.onFavoriteChanged(_favorite);
      _notify(_favorite ? '즐겨찾기에 추가했어요.' : '즐겨찾기에서 뺐어요.');
    } catch (_) {
      _notify('즐겨찾기를 변경하지 못했어요.', error: true);
    } finally {
      if (mounted) setState(() => _changingFavorite = false);
    }
  }

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
        _notify(success);
      }
    } on MediaActionException catch (error) {
      _notify(error.message, error: true);
    } catch (_) {
      _notify('작업을 완료하지 못했어요.', error: true);
    }
  }

  Future<void> _saveToLibrary() async {
    final media = _media;
    if (media == null || !widget.asset.isWeb) {
      return;
    }
    try {
      await widget.services.saveToLibrary(media, title: widget.asset.title);
      _notify('내 짤에 저장했어요.');
    } catch (_) {
      _notify('저장하지 못했어요.', error: true);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: _favorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                            onPressed: _changingFavorite || _busy
                                ? null
                                : _toggleFavorite,
                            icon: Icon(
                              _favorite ? Icons.star : Icons.star_border,
                              color: _favorite
                                  ? MemeTheme.accent
                                  : MemeTheme.text,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            tooltip: '미리보기 닫기',
                          ),
                        ],
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
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
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
                                  : Image.memory(
                                      _media!.bytes,
                                      fit: BoxFit.contain,
                                    ),
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
                          if (Platform.isWindows &&
                              !_previewOnly &&
                              !displayed.isGif)
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
                                  : () => _run(
                                      widget.actions.share,
                                      '공유 화면을 열었어요.',
                                    ),
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
                                  widget.asset.sourceUrl ??
                                      widget.asset.originalUrl!,
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
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Semantics(
                  liveRegion: true,
                  child: _InlineMessage(
                    message: _feedback!,
                    error: _feedbackIsError,
                  ),
                ),
              ),
          ],
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
      child: Text(
        message,
        style: const TextStyle(
          color: MemeTheme.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
