// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_glass.dart';
import '../services/audio_prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/api_service.dart';

import '../services/browse_service.dart';
import '../services/recommendation_engine.dart';
import '../widgets/aurum_stacked_artwork.dart';
import '../providers/player_provider.dart';
import '../providers/recently_played_provider.dart';
import '../theme/aurum_theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/faded_horizontal_list.dart';
import '../widgets/aurum_loader.dart';
import '../widgets/aurum_morph_loader.dart';
import '../widgets/aurum_empty_state.dart';
import '../widgets/aurum_equalizer_bars.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_transitions.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'mix_screen.dart';
import 'moods_genres_screen.dart';
import '../utils/aurum_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/aurum_image_cache.dart';

final _seenStaggeredItems = <String>{};
final _seenStaggeredOrder = <String>[];
const _maxSeenStaggeredItems = 500;

void _markStaggeredSeen(String key) {
  _seenStaggeredItems.add(key);
  _seenStaggeredOrder.add(key);
  if (_seenStaggeredOrder.length > _maxSeenStaggeredItems) {
    final evict = _seenStaggeredOrder.removeAt(0);
    if (!_seenStaggeredOrder.contains(evict)) _seenStaggeredItems.remove(evict);
  }
}

class _StaggeredItem extends StatefulWidget {
  final int index;
  final Widget child;
  final String? itemKey;
  const _StaggeredItem({required this.index, required this.child, this.itemKey});

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>?   _fade;
  Animation<Offset>?   _slide;
  bool _alreadySettled = false;

  @override
  void initState() {
    super.initState();
    final seenKey = widget.itemKey ?? 'idx_${widget.index}';
    if (_seenStaggeredItems.contains(seenKey)) {
      _alreadySettled = true;
      return;
    }
    _markStaggeredSeen(seenKey);

    final cappedIndex = widget.index.clamp(0, 10);
    final ctrl = AnimationController(
      vsync: this,
      duration: AurumMotion.durationOrZero(AurumMotion.long1),
    );
    _ctrl = ctrl;
    _fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: ctrl, curve: AurumMotion.standard));

    Future.delayed(Duration(milliseconds: 20 + cappedIndex * 35), () {
      if (mounted) ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_alreadySettled) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (_, child) => FadeTransition(
        opacity: _fade!,
        child: SlideTransition(position: _slide!, child: child),
      ),
      child: widget.child,
    );
  }
}

enum SearchResultFilter { all, songs, albums, artists, communityPlaylists, featuredPlaylists }

class SearchScreen extends StatefulWidget {
  final bool isActive;
  const SearchScreen({super.key, this.isActive = true});

  static final ValueNotifier<int> focusRequest = ValueNotifier<int>(0);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();

  List<Song>   _results        = [];
  int _searchGeneration = 0;
  List<ArtistSimple> _artistResults = [];
  List<BrowseAlbum> _albumResults = [];
  SearchResultFilter _activeFilter = SearchResultFilter.all;
  List<SearchPlaylistResult> _communityPlaylistResults = [];
  bool _communityPlaylistsLoading = false;
  String _lastCommunityPlaylistQuery = '';
  List<SearchPlaylistResult> _featuredPlaylistResults = [];
  bool _featuredPlaylistsLoading = false;
  List<Song>   _relatedResults = [];
  List<Song>   _liveResults = [];
  List<String> _suggestions = [];
  List<String> _history     = [];
  List<List<Song>> _resultQueues = [];
  List<List<Song>> _relatedQueues = [];
  bool _loading     = false;
  bool _liveLoading = false;
  bool _showLiveLoader = false;
  Timer? _liveLoaderGraceTimer;
  bool _showHistory = false;

  int _landingTabIndex = 0;
  List<MoodGenreSection>? _moodSections;

  String _bodyKeyBeforeThisBuild = 'empty';

  Timer? _debounce;
  Timer? _suggestDebounce;

  static const _prefKey    = 'aurum_search_history';
  static const _maxHistory = 10;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _focusNode.addListener(_onFocusChange);
    SearchScreen.focusRequest.addListener(_onFocusRequest);
    ApiService.wakeSaavn();
    _applyActiveState();
    _loadMoodGenres();
  }

  Future<void> _loadMoodGenres() async {
    final cached = await MoodGenreCacheStore.load();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() => _moodSections = cached);
    }
    final fresh = await MoodGenreCacheStore.isFresh();
    if (cached != null && cached.isNotEmpty && fresh) return;
    final base = await ApiService.fetchMoodsAndGenres(withArtwork: false);
    if (!mounted || base.isEmpty) return;
    final withOld = (cached != null && cached.isNotEmpty)
        ? await ApiService.topupMoodGenreArtworkFrom(base, cached)
        : base;
    if (!mounted) return;
    setState(() => _moodSections = withOld);
    final full = await ApiService.topupMoodGenreArtwork(withOld);
    if (!mounted) return;
    setState(() => _moodSections = full);
    unawaited(MoodGenreCacheStore.save(full));
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    _applyActiveState();
  }

  void _applyActiveState() {
    if (!widget.isActive) {
      if (_focusNode.hasFocus) _focusNode.unfocus();
      _focusNode.canRequestFocus = false;
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } else {
      _focusNode.canRequestFocus = true;
    }
  }

  void _onFocusRequest() {
    if (!mounted || !widget.isActive) return;
    if (!_focusNode.canRequestFocus) _focusNode.canRequestFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      if (_controller.text.trim().isEmpty && _history.isNotEmpty && !_showHistory) {
        setState(() => _showHistory = true);
      }
    });
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focusNode.hasFocus) ApiService.wakeSaavn(fromSearchFocus: true);
    final shouldShowHistory =
        _focusNode.hasFocus && _controller.text.trim().isEmpty && _history.isNotEmpty;
    if (shouldShowHistory != _showHistory) {
      setState(() => _showHistory = shouldShowHistory);
    }
  }

  void _dismissKeyboard() {
    if (_focusNode.hasFocus) {
      _suggestDebounce?.cancel();
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    SearchScreen.focusRequest.removeListener(_onFocusRequest);
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _liveLoaderGraceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { _history = prefs.getStringList(_prefKey) ?? []; });
  }

  Future<void> _saveToHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _history.remove(q);
    _history.insert(0, q);
    if (_history.length > _maxHistory) _history = _history.sublist(0, _maxHistory);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _history);
    if (mounted) setState(() {});
  }

  Future<void> _removeFromHistory(String query) async {
    _history.remove(query);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _history);
    if (mounted) setState(() {});
  }

  Future<void> _clearHistory() async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    if (mounted) setState(() => _showHistory = false);
  }

  void _onChanged(String q) {
    _suggestDebounce?.cancel();
    _liveLoaderGraceTimer?.cancel();
    final query = q.trim();

    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _suggestions  = [];
        _liveResults  = [];
        _liveLoading  = false;
        _showLiveLoader = false;
        _showHistory  = _history.isNotEmpty && _focusNode.hasFocus;
        _artistResults = [];
        _albumResults = [];
      });
      return;
    }

    if (_showHistory || !_liveLoading || _showLiveLoader) {
      setState(() { _showHistory = false; _liveLoading = true; _showLiveLoader = false; });
    }

    _liveLoaderGraceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_controller.text.trim() != query) return;
      if (_liveLoading) setState(() => _showLiveLoader = true);
    });

    _suggestDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      if (_controller.text.trim() != query) return;

      ApiService.quickSearch(query).then((songs) {
        if (!mounted) return;
        if (_controller.text.trim() != query) return;
        final playedIds = context.read<RecentlyPlayedProvider>().playedIdSet;
        final boosted = playedIds.isEmpty
            ? songs
            : [
                ...songs.where((s) => playedIds.contains(s.id)),
                ...songs.where((s) => !playedIds.contains(s.id)),
              ];
        setState(() {
          _liveResults = boosted;
          _liveLoading = false;
          _showLiveLoader = false;
        });
      }).catchError((_) {
        if (!mounted) return;
        if (_controller.text.trim() != query) return;
        setState(() { _liveLoading = false; _showLiveLoader = false; });
      });

      ApiService.suggest(query).then((suggestions) {
        if (!mounted || _controller.text.trim() != query) return;
        setState(() => _suggestions = suggestions);
      }).catchError((_) {});

      final myLiveGeneration = ++_searchGeneration;
      if (query.length >= 3 && !AudioPrefs.dataSaverActiveNotifier.value) {
        ApiService.searchArtists(query).then((artists) {
          if (!mounted || myLiveGeneration != _searchGeneration) return;
          setState(() { _artistResults = artists; });
        }).catchError((_) {});
        ApiService.searchAlbums(query).then((albums) {
          if (!mounted || myLiveGeneration != _searchGeneration) return;
          setState(() { _albumResults = albums; });
        }).catchError((_) {});
      }

    });
  }

  void _precomputeResultQueues() {
    _resultQueues = _buildDedupQueues(_results);
  }

  List<List<Song>> _buildDedupQueues(List<Song> src) {
    final cap = src.length < _maxRelatedQueueAnchors
        ? src.length
        : _maxRelatedQueueAnchors;
    final scanLimit = src.length < _maxRelatedQueueScan
        ? src.length
        : _maxRelatedQueueScan;
    final isVariant = List<bool?>.filled(scanLimit, null);
    final memo = <int, bool>{};
    bool same(int cand, int kept, String candTitle, String keptTitle) {
      final key = cand * 1000 + kept;
      return memo[key] ??= RecommendationEngine.isSameSongSmart(candTitle, keptTitle);
    }

    return List.generate(cap, (tappedIndex) {
      final anchor = src[tappedIndex];
      final seenIds = <String>{anchor.id};
      final keptIdx = <int>[tappedIndex];
      final out = <Song>[anchor];
      for (int j = 0; j < scanLimit; j++) {
        if (j == tappedIndex) continue;
        final cand = src[j];
        if (seenIds.contains(cand.id)) continue;
        final variant = isVariant[j] ??=
            RecommendationEngine.isInherentVariant(cand.title);
        if (variant) continue;
        var isDup = false;
        for (final k in keptIdx) {
          if (same(j, k, cand.title, src[k].title)) {
            isDup = true;
            break;
          }
        }
        if (isDup) continue;
        seenIds.add(cand.id);
        keptIdx.add(j);
        out.add(cand);
      }
      return out;
    });
  }

  static const int _maxRelatedQueueAnchors = 40;
  static const int _maxRelatedQueueScan = 40;

  void _precomputeRelatedQueues() {
    _relatedQueues = _buildDedupQueues(_relatedResults);
  }

  void _search(String q) {
    AnalyticsService.instance.logSearch(q);
    final query = q.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _liveLoaderGraceTimer?.cancel();
    AurumHaptics.light();
    _dismissKeyboard();
    setState(() {
      _loading = true;
      _liveLoading = false;
      _showLiveLoader = false;
      _showHistory = false;
      _results = [];
      _artistResults = [];
      _albumResults = [];
      _activeFilter = SearchResultFilter.all;
      _suggestions = [];
      _resultQueues = [];
      _relatedQueues = [];
    });
    final myGeneration = ++_searchGeneration;
    _saveToHistory(query);
    ApiService.searchArtists(query).then((artists) {
      if (!mounted || myGeneration != _searchGeneration) return;
      setState(() { _artistResults = artists; });
    });
    ApiService.searchAlbums(query).then((albums) {
      if (!mounted || myGeneration != _searchGeneration) return;
      setState(() { _albumResults = albums; });
    });
    final liveYtSnapshot = _liveResults
        .where((s) => s.source == SongSource.youtube)
        .toList();
    final hasGoodLiveYt = liveYtSnapshot.length >= 5;

    if (hasGoodLiveYt) {
      setState(() {
        _results = liveYtSnapshot;
        _loading = false;
      });
      _precomputeResultQueues();
    }

    _debounce = Timer(const Duration(milliseconds: 150), () async {
      SearchResult result;
      try {
        result = await ApiService.search(query);
      } catch (_) {
        if (!mounted || _controller.text.trim() != query) return;
        if (!hasGoodLiveYt) setState(() { _loading = false; });
        return;
      }
      if (!mounted || _controller.text.trim() != query) return;

      List<Song> dedupedRelated = result.related;
      if (hasGoodLiveYt) {
        final liveIds = liveYtSnapshot.map((s) => s.id).toSet();
        const maxLiveTitlesToCheck = 25;
        final liveRawTitles = liveYtSnapshot
            .map((s) => s.title)
            .take(maxLiveTitlesToCheck)
            .toList();
        bool isDupOfLive(Song s) {
          if (liveIds.contains(s.id)) return true;
          for (final t in liveRawTitles) {
            if (RecommendationEngine.isSameSongSmart(s.title, t)) return true;
          }
          return false;
        }
        const maxCandidatesToDedup = 150;
        dedupedRelated = <Song>[
          ...result.direct.take(maxCandidatesToDedup).where((s) => !isDupOfLive(s)),
          ...result.related.take(maxCandidatesToDedup).where((s) => !isDupOfLive(s)),
        ];
      }

      setState(() {
        if (!hasGoodLiveYt) _results = result.direct;
        _relatedResults = dedupedRelated;
        _loading = false;
      });
      if (!hasGoodLiveYt) _precomputeResultQueues();
      _precomputeRelatedQueues();
    });
  }

  void _recordSelection(String query, Song song) {
    if (query.trim().isEmpty) return;
    ApiService.recordSearchSelection(query, song);
  }

  void _clearSearch() {
    AurumHaptics.light();
    _suggestDebounce?.cancel();
    _debounce?.cancel();
    _liveLoaderGraceTimer?.cancel();
    _controller.clear();
    _searchGeneration++;
    setState(() {
      _results = []; _relatedResults = []; _liveResults = []; _suggestions = [];
      _artistResults = [];
      _albumResults = [];
      _activeFilter = SearchResultFilter.all;
      _liveLoading = false; _showLiveLoader = false; _loading = false;
      _showHistory = _history.isNotEmpty;
      _resultQueues = []; _relatedQueues = [];
    });
  }

  void _goToLanding() {
    AurumHaptics.light();
    _suggestDebounce?.cancel();
    _debounce?.cancel();
    _liveLoaderGraceTimer?.cancel();
    _dismissKeyboard();
    _controller.clear();
    _searchGeneration++;
    setState(() {
      _results = []; _relatedResults = []; _liveResults = []; _suggestions = [];
      _artistResults = [];
      _albumResults = [];
      _activeFilter = SearchResultFilter.all;
      _liveLoading = false; _showLiveLoader = false; _loading = false;
      _showHistory = false;
      _resultQueues = []; _relatedQueues = [];
    });
  }

  bool get _hasVisibleContent =>
      _results.isNotEmpty ||
      (_controller.text.trim().isNotEmpty && _liveResults.isNotEmpty);

  String _computeBodyKey() {
    if (_loading && !_hasVisibleContent) return 'loading';
    if (_results.isNotEmpty) return 'results';
    if (_controller.text.trim().isNotEmpty) return 'live';
    if (_showHistory && _history.isNotEmpty) return 'history';
    return 'empty';
  }

  @override
  Widget build(BuildContext context) {
    final previousBodyKey = _bodyKeyBeforeThisBuild;
    final currentBodyKey = _computeBodyKey();
    _bodyKeyBeforeThisBuild = currentBodyKey;
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context),
              _buildSearchBar(context),
              _buildFilterChips(context),
              Expanded(
                child: _KeyboardInsetPadding(
                  child:
                    AnimatedSwitcher(
                      duration: (previousBodyKey == 'empty' && currentBodyKey == 'live')
                          ? const Duration(milliseconds: 80)
                          : const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.05),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: AurumMotion.standard));
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slide,
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(currentBodyKey),
                        child: _buildBody(context),
                      ),
                    ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    final hasAnyResults = _results.isNotEmpty || _artistResults.isNotEmpty || _albumResults.isNotEmpty;
    if (!hasQuery || !hasAnyResults) {
      return const SizedBox.shrink();
    }
    final chips = <(SearchResultFilter, String, IconData)>[
      (SearchResultFilter.all, 'All', Icons.check_rounded),
      (SearchResultFilter.songs, 'Songs', Icons.music_note_rounded),
      (SearchResultFilter.albums, 'Albums', Icons.album_rounded),
      (SearchResultFilter.artists, 'Artists', Icons.person_rounded),
      (SearchResultFilter.communityPlaylists, 'Community playlists', Icons.groups_rounded),
      (SearchResultFilter.featuredPlaylists, 'Featured playlists', Icons.playlist_play_rounded),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (filter, label, icon) = chips[i];
          final selected = _activeFilter == filter;
          return _PressScale(
            onTap: () {
              if (selected) return;
              setState(() => _activeFilter = filter);
              if (filter == SearchResultFilter.communityPlaylists) {
                _fetchCommunityPlaylists(_controller.text.trim());
              } else if (filter == SearchResultFilter.featuredPlaylists) {
                _fetchFeaturedPlaylists();
              }
            },
            child: AnimatedContainer(
              duration: AurumMotion.durationOrZero(AurumMotion.medium1),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected ? AurumTheme.accentGradientOf(context) : null,
                color: selected ? null : AurumTheme.bgCardOf(context),
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? null
                    : Border.all(color: AurumTheme.dividerOf(context), width: 0.6),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AurumTheme.accentOf(context).withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? Colors.black : AurumTheme.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.black : AurumTheme.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumsFilterView(BuildContext context) {
    if (_albumResults.isEmpty) {
      return _buildEmptyFilterState(context, 'No albums found');
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      key: const ValueKey('albums_filter'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, _searchBottomClearance(context)),
      itemCount: _albumResults.length,
      itemBuilder: (context, i) {
        final album = _albumResults[i];
        return _buildAlbumFilterRow(context, album);
      },
    );
  }

  Widget _buildAlbumFilterRow(BuildContext context, BrowseAlbum album) {
    return AurumPressable(
      onTap: () => _openAlbumFromSearch(context, album),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AurumArtwork(url: album.artworkUrl, size: 52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (album.artist.isNotEmpty) album.artist,
                      if (album.releaseYear != null) album.releaseYear!,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AurumTheme.textSecondaryOf(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistsFilterView(BuildContext context) {
    if (_artistResults.isEmpty) {
      return _buildEmptyFilterState(context, 'No artists found');
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      key: const ValueKey('artists_filter'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, _searchBottomClearance(context)),
      itemCount: _artistResults.length,
      itemBuilder: (context, i) => _buildArtistListTile(context, _artistResults[i]),
    );
  }

  Widget _buildEmptyFilterState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Text(
          message,
          style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 14),
        ),
      ),
    );
  }

  Future<void> _fetchCommunityPlaylists(String query) async {
    if (!mounted || query.isEmpty) return;
    if (query == _lastCommunityPlaylistQuery && _communityPlaylistResults.isNotEmpty) return;
    _lastCommunityPlaylistQuery = query;
    setState(() => _communityPlaylistsLoading = true);
    List<SearchPlaylistResult> results;
    try {
      results = await ApiService.searchPlaylists(query);
    } catch (_) {
      if (mounted && _lastCommunityPlaylistQuery == query) {
        setState(() => _communityPlaylistsLoading = false);
      }
      return;
    }
    if (mounted && _lastCommunityPlaylistQuery == query) {
      setState(() {
        _communityPlaylistResults = results;
        _communityPlaylistsLoading = false;
      });
    }
  }

  Widget _buildCommunityPlaylistsFilterView(BuildContext context) {
    if (_communityPlaylistsLoading && _communityPlaylistResults.isEmpty) {
      return const Center(child: AurumMorphLoader(contained: true));
    }
    if (_communityPlaylistResults.isEmpty) {
      return _buildEmptyFilterState(context, 'No community playlists found');
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      key: const ValueKey('community_playlists_filter'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, _searchBottomClearance(context)),
      itemCount: _communityPlaylistResults.length,
      itemBuilder: (context, i) =>
          _buildPlaylistResultTile(context, _communityPlaylistResults[i]),
    );
  }

  Future<void> _fetchFeaturedPlaylists() async {
    if (!mounted || _featuredPlaylistResults.isNotEmpty) return;
    setState(() => _featuredPlaylistsLoading = true);
    List<SearchPlaylistResult> results;
    try {
      results = await ApiService.fetchFeaturedPlaylistsForSearch();
      if (results.isEmpty) {
        results = await ApiService.fetchFeaturedPlaylistsForSearch();
      }
      if (results.isEmpty) {
        final q = _controller.text.trim();
        if (q.isNotEmpty) results = await ApiService.searchPlaylists(q);
      }
    } catch (_) {
      if (mounted) setState(() => _featuredPlaylistsLoading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _featuredPlaylistResults = results;
        _featuredPlaylistsLoading = false;
      });
    }
  }

  Widget _buildFeaturedPlaylistsFilterView(BuildContext context) {
    if (_featuredPlaylistsLoading && _featuredPlaylistResults.isEmpty) {
      return const Center(child: AurumMorphLoader(contained: true));
    }
    if (_featuredPlaylistResults.isEmpty) {
      return _buildEmptyFilterState(context, 'No featured playlists found');
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      key: const ValueKey('featured_playlists_filter'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, _searchBottomClearance(context)),
      itemCount: _featuredPlaylistResults.length,
      itemBuilder: (context, i) =>
          _buildPlaylistResultTile(context, _featuredPlaylistResults[i]),
    );
  }

  Widget _buildPlaylistResultTile(
    BuildContext context,
    SearchPlaylistResult playlist,
  ) {
    return AurumPressable(
      scaleAmount: 0.97,
      onTap: () {
        AurumHaptics.light();
        _dismissKeyboard();
        AurumDepthRoute.to(
          context,
          MixScreen(
            mixId: playlist.id,
            mixName: playlist.title,
            artworkUrl: playlist.artworkUrl,
            emoji: '',
            songs: const [],
            autoLoadStream: () =>
                ApiService.streamCommunityPlaylistSongs(playlist.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AurumArtwork(url: playlist.artworkUrl, size: 56),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.author.isNotEmpty ? playlist.author : 'Playlist',
                    style: TextStyle(
                      color: AurumTheme.textSecondaryOf(context),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AurumTheme.textMutedOf(context), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && !_hasVisibleContent) {
      return const Center(key: ValueKey('loading'), child: AurumMorphLoader(size: 56, contained: true));
    }
    if (_activeFilter == SearchResultFilter.albums) {
      return _buildAlbumsFilterView(context);
    }
    if (_activeFilter == SearchResultFilter.artists) {
      return _buildArtistsFilterView(context);
    }
    if (_activeFilter == SearchResultFilter.communityPlaylists) {
      return _buildCommunityPlaylistsFilterView(context);
    }
    if (_activeFilter == SearchResultFilter.featuredPlaylists) {
      return _buildFeaturedPlaylistsFilterView(context);
    }
    if (_results.isNotEmpty) return _buildResults();
    if (_controller.text.trim().isNotEmpty) return _buildLivePanel(context);
    if (_showHistory && _history.isNotEmpty) return _buildHistory(context);
    return _buildEmpty(context);
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        ShaderMask(
          shaderCallback: (b) => AurumTheme.accentGradientOf(context).createShader(b),
          child: Text(l10n.searchTabSearch, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
        ),
      ]),
    );
  }

  late final Listenable _searchBarListenable =
      Listenable.merge([_focusNode, _controller]);

  Widget _buildSearchBar(BuildContext context) {
    return ListenableBuilder(
      listenable: _searchBarListenable,
      builder: (ctx, _) => _buildSearchBarContent(ctx),
    );
  }

  Widget _buildSearchBarContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final focused = _focusNode.hasFocus;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = focused
        ? AurumTheme.accentOf(context).withOpacity(0.6)
        : (isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08));
    final textField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      onTap: () {
        if (!_focusNode.canRequestFocus) _focusNode.canRequestFocus = true;
        if (!_focusNode.hasFocus) _focusNode.requestFocus();
        if (_controller.text.trim().isEmpty && _history.isNotEmpty && !_showHistory) {
          setState(() => _showHistory = true);
        }
      },
      onChanged: _onChanged,
      onSubmitted: _search,
      style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: l10n.searchHint,
        hintStyle: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded,
            color: focused ? AurumTheme.accentOf(context) : AurumTheme.textMutedOf(context), size: 20),
        suffixIcon: (focused || _controller.text.isNotEmpty || _showHistory)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.text.isNotEmpty)
                    AurumPressable(
                      scaleAmount: 0.82,
                      onTap: _clearSearch,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.close_rounded, color: AurumTheme.textMutedOf(context), size: 18),
                      ),
                    ),
                  AurumPressable(
                    scaleAmount: 0.82,
                    onTap: _goToLanding,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      child: Icon(Icons.arrow_back_rounded, color: AurumTheme.textMutedOf(context), size: 20),
                    ),
                  ),
                ],
              )
            : null,
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
      textInputAction: TextInputAction.search,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ValueListenableBuilder<bool>(
        valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
        builder: (context, glassOn, child) {
          final blurSigma = glassOn ? AudioPrefs.glassNavSigma : 0.0;
          return AnimatedContainer(
          duration: AurumMotion.durationOrZero(AurumMotion.medium1),
          curve: Curves.easeOut,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: focused ? 1.3 : 0.7),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: AurumTheme.accentOf(context).withOpacity(0.16),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: AurumGlass(
            sigma: blurSigma,
            borderRadius: BorderRadius.circular(14),
            isDark: isDark,
            tintColor: isDark
                ? Colors.white.withOpacity(0.06)
                : AurumTheme.darkBgCard.withOpacity(0.05),
            child: child!,
          ),
          );
        },
        child: textField,
      ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: const ValueKey('history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.searchRecent, style: TextStyle(color: AurumTheme.textSecondaryOf(context), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              TextButton(
                onPressed: _clearHistory,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l10n.searchClearAll, style: TextStyle(color: AurumTheme.accentOf(context).withOpacity(0.8), fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 600,
            padding: EdgeInsets.only(bottom: _searchBottomClearance(context)),
            itemCount: _history.length,
            itemExtent: 52,
            itemBuilder: (_, i) {
              final item = _history[i];
              return ListTile(
                leading: Icon(Icons.history_rounded, color: AurumTheme.textMutedOf(context), size: 18),
                title: Text(item, style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AurumPressable(
                      scaleAmount: 0.80,
                      onTap: () { _controller.text = item; _controller.selection = TextSelection.fromPosition(TextPosition(offset: item.length)); _onChanged(item); },
                      child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.north_west_rounded, color: AurumTheme.textMutedOf(context), size: 16)),
                    ),
                    AurumPressable(
                      scaleAmount: 0.80,
                      onTap: () => _removeFromHistory(item),
                      child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.close_rounded, color: AurumTheme.textMutedOf(context), size: 16)),
                    ),
                  ],
                ),
                dense: true,
                onTap: () { _controller.text = item; _search(item); },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLivePanel(BuildContext context) {
    final query          = _controller.text.trim();
    final hasSuggestions = _suggestions.isNotEmpty;
    final hasLive        = _liveResults.isNotEmpty;

    Widget content;
    if (!hasSuggestions && !hasLive) {
      content = _liveLoading
          ? (_showLiveLoader ? _buildLiveLoadingState(context) : const SizedBox.shrink())
          : _buildNoLiveResults(context, query);
    } else {
      final showArtistAlbumHeaderLive = _activeFilter == SearchResultFilter.all &&
          (_artistResults.isNotEmpty || _albumResults.isNotEmpty);
      final artistAlbumHeaderCount = showArtistAlbumHeaderLive ? 1 : 0;
      final headerCount = (_liveLoading ? 1 : 0)
          + (hasSuggestions ? _suggestions.length + (hasLive ? 1 : 0) : 0)
          + (hasLive ? 1 : 0);
      final tailCount = query.isNotEmpty ? 1 : 0;
      final totalCount = artistAlbumHeaderCount + headerCount + (hasLive ? _liveResults.length : 0) + tailCount;

      content = RepaintBoundary(child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(bottom: _searchBottomClearance(context)),
        itemCount: totalCount,
        cacheExtent: 600,
        itemBuilder: (context, rawI) {
          var i = rawI;
          if (showArtistAlbumHeaderLive) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildArtistSection(context),
                  _buildAlbumSection(context),
                ],
              );
            }
            i--;
          }
          var idx = i;
          if (_liveLoading) {
            if (idx == 0) return _buildLiveProgressBar(context);
            idx--;
          }
          if (hasSuggestions) {
            if (idx < 0 || idx >= _suggestions.length + (hasLive ? _liveResults.length + 2 : 0) + (hasLive ? 1 : 0)) {
              return const SizedBox.shrink();
            }
            if (idx < _suggestions.length) return _suggestionTile(context, _suggestions[idx]);
            idx -= _suggestions.length;
            if (hasLive) {
              if (idx == 0) {
                return Divider(color: AurumTheme.dividerOf(context), height: 1, indent: 16, endIndent: 16);
              }
              idx--;
            }
          }
          if (hasLive) {
            if (idx == 0) return _sectionLabel(context, AppLocalizations.of(context)!.librarySongs);
            idx--;
            if (idx < 0 || idx >= _liveResults.length) return const SizedBox.shrink();
            if (idx < _liveResults.length) {
              final song = _liveResults[idx];
              return SizedBox(
                height: 86,
                child: _StaggeredItem(
                  index: idx,
                  itemKey: 'live_${song.id}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (_) => _recordSelection(query, song),
                    child: SongTile(
                      key: ValueKey('live_${song.id}'),
                      song: song, queue: _liveResults, index: idx,
                    ),
                  ),
                ),
              );
            }
            idx -= _liveResults.length;
          }
          return _seeAllTile(context, query);
        },
      ));
    }

    return KeyedSubtree(
      key: const ValueKey('live'),
      child: content,
    );
  }

  Widget _buildLiveProgressBar(BuildContext context) {
    return const SizedBox(height: 2, child: AurumM3Loader(height: 2));
  }

  Widget _buildLiveLoadingState(BuildContext context) {
    return Column(children: [
      _buildLiveProgressBar(context),
      const Expanded(child: Center(child: AurumMorphLoader(size: 56, contained: true))),
    ]);
  }

  Widget _buildNoLiveResults(BuildContext context, String query) {
    final l10n = AppLocalizations.of(context)!;
    return AurumEmptyState(
      icon: Icons.search_off_rounded,
      title: l10n.searchNoResultsFor(query),
      actionLabel: l10n.searchEverywhere,
      onAction: () {
        AurumHaptics.light();
        _search(query);
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(label.toUpperCase(), style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
    );
  }

  Widget _topResultsHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              gradient: AurumTheme.accentGradientOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Top results',
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionTile(BuildContext context, String s) {
    return ListTile(
      key: ValueKey('sugg_$s'),
      leading: Icon(Icons.search_rounded, color: AurumTheme.textMutedOf(context), size: 18),
      title: Text(s, style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: AurumPressable(
        scaleAmount: 0.80,
        haptic: false,
        onTap: () { AurumHaptics.light(); _controller.text = s; _controller.selection = TextSelection.fromPosition(TextPosition(offset: s.length)); _onChanged(s); },
        child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.north_west_rounded, color: AurumTheme.textMutedOf(context), size: 16)),
      ),
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      onTap: () { _controller.text = s; _search(s); },
    );
  }

  Widget _seeAllTile(BuildContext context, String query) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      key: const ValueKey('see_all'),
      leading: Icon(Icons.travel_explore_rounded, color: AurumTheme.accentOf(context), size: 20),
      title: Text(l10n.searchSeeAllResultsFor(query), style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: AurumTheme.accentOf(context).withOpacity(0.6), size: 14),
      dense: true,
      onTap: () => _search(query),
    );
  }

  Widget _buildResults() {
    final l10n = AppLocalizations.of(context)!;
    if (_activeFilter == SearchResultFilter.albums) {
      return _buildAlbumsFilterView(context);
    }
    if (_activeFilter == SearchResultFilter.artists) {
      return _buildArtistsFilterView(context);
    }
    if (_activeFilter == SearchResultFilter.communityPlaylists) {
      return _buildCommunityPlaylistsFilterView(context);
    }
    if (_activeFilter == SearchResultFilter.featuredPlaylists) {
      return _buildFeaturedPlaylistsFilterView(context);
    }
    final showRelatedHeader = _relatedResults.isNotEmpty;
    final itemCount = _results.length
        + (showRelatedHeader ? 1 : 0)
        + _relatedResults.length;

    final showArtistAlbumHeader = _activeFilter == SearchResultFilter.all &&
        (_artistResults.isNotEmpty || _albumResults.isNotEmpty);
    final showTopResultsHeader = _activeFilter == SearchResultFilter.all &&
        (_results.isNotEmpty || showArtistAlbumHeader);
    final headerItemCount = (showTopResultsHeader ? 1 : 0) + (showArtistAlbumHeader ? 1 : 0);

    return Stack(
      children: [
        RepaintBoundary(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            key: const ValueKey('results'),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 800,
            itemCount: headerItemCount + itemCount,
            padding: EdgeInsets.only(bottom: _searchBottomClearance(context)),
            itemBuilder: (_, rawIndex) {
              if (showTopResultsHeader && rawIndex == 0) {
                return _topResultsHeader(context);
              }
              final afterTopIndex = rawIndex - (showTopResultsHeader ? 1 : 0);
              if (showArtistAlbumHeader && afterTopIndex == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildArtistSection(context),
                    _buildAlbumSection(context),
                  ],
                );
              }
              final i = afterTopIndex - (showArtistAlbumHeader ? 1 : 0);
            if (i >= _results.length + (showRelatedHeader ? 1 : 0) + _relatedResults.length) {
              return const SizedBox.shrink();
            }
            if (i < _results.length) {
              return SizedBox(
                height: 86,
                child: _StaggeredItem(
                  index: i,
                  itemKey: 'result_${_results[i].id}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (_) => _recordSelection(_controller.text, _results[i]),
                    child: SongTile(
                      key: ValueKey('result_${_results[i].id}'),
                      song: _results[i],
                      queue: i < _resultQueues.length ? _resultQueues[i] : [_results[i]],
                      index: 0,
                    ),
                  ),
                ),
              );
            }
            final headerIdx = _results.length;
            if (showRelatedHeader && i == headerIdx) {
              return _sectionLabel(context, l10n.searchYouMightAlsoLike);
            }
            final relatedIdx = i - _results.length - (showRelatedHeader ? 1 : 0);
            if (relatedIdx < 0 || relatedIdx >= _relatedResults.length) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              height: 86,
              child: _StaggeredItem(
                index: i,
                itemKey: 'related_${_relatedResults[relatedIdx].id}',
                child: SongTile(
                  key: ValueKey('related_${_relatedResults[relatedIdx].id}'),
                  song: _relatedResults[relatedIdx],
                  queue: relatedIdx < _relatedQueues.length
                      ? _relatedQueues[relatedIdx]
                      : [_relatedResults[relatedIdx]],
                  index: 0,
                ),
              ),
            );
          },
          ),
        ),
        if (_loading)
          const Positioned(
            top: 0, left: 0, right: 0,
            child: SizedBox(height: 2, child: AurumM3Loader(height: 2)),
          ),
      ],
    );
  }

  static const int _maxVisibleArtists = 4;

  Widget _buildArtistSection(BuildContext context) {
    if (_artistResults.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final hasMore = _artistResults.length > _maxVisibleArtists;
    final visible = hasMore
        ? _artistResults.sublist(0, _maxVisibleArtists)
        : _artistResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Icon(Icons.person_rounded, color: AurumTheme.accentOf(context), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.libraryArtists,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasMore)
                GestureDetector(
                  onTap: () {
                    AurumHaptics.selection();
                    setState(() => _activeFilter = SearchResultFilter.artists);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Text(
                      l10n.commonSeeAll,
                      style: TextStyle(
                        color: AurumTheme.textSecondaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ...List.generate(visible.length, (i) {
          final a = visible[i];
          return _buildArtistListTile(context, a);
        }),
      ],
    );
  }

  Widget _buildArtistListTile(BuildContext context, ArtistSimple a) {
    return AurumPressable(
      onTap: () {
        AurumHaptics.light();
        Navigator.push(
          context,
          AurumDepthRoute(
            builder: (_) => ArtistScreen(artistId: a.id, artistName: a.name),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipOval(child: AurumArtwork(url: a.imageUrl, size: 56)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Artist',
                    style: TextStyle(
                      color: AurumTheme.textSecondaryOf(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AurumTheme.textMutedOf(context), size: 22),
          ],
        ),
      ),
    );
  }

  static const int _maxVisibleAlbums = 10;

  Widget _buildAlbumSection(BuildContext context) {
    if (_albumResults.isEmpty) return const SizedBox.shrink();
    final hasMore = _albumResults.length > _maxVisibleAlbums;
    final visible = hasMore
        ? _albumResults.sublist(0, _maxVisibleAlbums)
        : _albumResults;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Icon(Icons.album_rounded, color: AurumTheme.accentOf(context), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Albums',
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasMore)
                GestureDetector(
                  onTap: () {
                    AurumHaptics.selection();
                    setState(() => _activeFilter = SearchResultFilter.albums);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Text(
                      l10n.commonSeeAll,
                      style: TextStyle(
                        color: AurumTheme.textSecondaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: visible.length,
            itemBuilder: (context, i) => _AlbumCard(
              album: visible[i],
              onTap: () => _openAlbumFromSearch(context, visible[i]),
            ),
          ),
        ),
      ],
    );
  }

  void _openAlbumFromSearch(BuildContext context, BrowseAlbum album) {
    AurumHaptics.light();
    Navigator.push(
      context,
      AurumDepthRoute(
        builder: (_) => AlbumScreen(
          albumId: album.collectionId,
          albumName: album.name,
          artworkUrl: album.artworkUrl,
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(
      key: const ValueKey('explore'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLandingSwitcher(context),
        Expanded(
          child: _landingTabIndex == 0
              ? _buildExploreGrid(context)
              : _buildSuggestionsLanding(context),
        ),
      ],
    );
  }

  Widget _buildLandingSwitcher(BuildContext context) {
    Widget tab(String label, int index) {
      final selected = _landingTabIndex == index;
      return Expanded(
        child: _PressScale(
          onTap: () {
            if (selected) return;
            setState(() => _landingTabIndex = index);
          },
          child: AnimatedContainer(
            duration: AurumMotion.durationOrZero(AurumMotion.medium1),
            curve: Curves.easeOut,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? AurumTheme.accentGradientOf(context) : null,
              color: selected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AurumTheme.accentOf(context).withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? Colors.black
                    : AurumTheme.textMutedOf(context),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AurumTheme.dividerOf(context), width: 0.6),
        ),
        child: Row(children: [tab('Explore', 0), const SizedBox(width: 4), tab('Suggestions', 1)]),
      ),
    );
  }

  Widget _buildExploreGrid(BuildContext context) {
    final sections = _moodSections;
    if (sections == null || sections.isEmpty) {
      return const Center(child: AurumMorphLoader(contained: true));
    }
    final seenTitles = <String>{};
    final tiles = <MoodGenreCategory>[];
    for (final section in sections) {
      for (final tile in section.items) {
        if (seenTitles.add(tile.title)) tiles.add(tile);
      }
    }
    return CustomScrollView(
      key: const ValueKey('explore_grid'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
              'Mood & Genres',
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, _searchBottomClearance(context)),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final tile = tiles[i];
                final color = tile.color != null
                    ? Color(tile.color!).withAlpha(255)
                    : AurumTheme.bgCardOf(context);
                return _ExploreMoodTile(
                  title: tile.title,
                  color: color,
                  artworkUrl: tile.artworkUrl,
                  onTap: () {
                    AurumHaptics.selection();
                    _dismissKeyboard();
                    AurumDepthRoute.to(
                      context,
                      MoodGenreDetailScreen(category: tile, tileColor: color),
                    );
                  },
                );
              },
              childCount: tiles.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionsLanding(BuildContext context) {
    return const _SuggestionsLanding();
  }
}

class _SuggestionsLanding extends StatefulWidget {
  const _SuggestionsLanding();

  @override
  State<_SuggestionsLanding> createState() => _SuggestionsLandingState();
}

class _SuggestionsLandingState extends State<_SuggestionsLanding> {
  List<Song>? _songs;
  List<({String artistName, List<ArtistSimple> related})>? _artistRows;
  List<BrowseAlbum>? _albums;
  bool _failed = false;
  String? _seedVideoId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final latest = context.watch<RecentlyPlayedProvider>().history.firstOrNull;
    final latestId = latest?.id;
    if (latestId != null && latestId != _seedVideoId) {
      _seedVideoId = latestId;
      _load();
    }
  }

  Future<void> _load() async {
    final myGeneration = ++_loadGeneration;
    final seedVideoId = _seedVideoId;
    final seedArtists = RecommendationEngine.rotatingAffinityArtists(count: 3);
    if ((seedVideoId == null || seedVideoId.isEmpty) && seedArtists.isEmpty) {
      if (mounted && myGeneration == _loadGeneration) setState(() => _failed = true);
      return;
    }
    try {
      final futureSongs = (seedVideoId != null && seedVideoId.isNotEmpty)
          ? ApiService.fetchYouMightAlsoLike(seedVideoId)
          : Future.value(<Song>[]);
      final futureArtistRows = Future.wait(
        seedArtists.map((a) => ApiService.fetchSimilarArtistChips(a)),
      );
      final futureAlbums = seedArtists.isNotEmpty
          ? ApiService.searchAlbumsYtOnly(seedArtists.first, limit: 8)
          : Future.value(<BrowseAlbum>[]);
      final songs = await futureSongs;
      final artistRowsRaw = await futureArtistRows;
      final albums = await futureAlbums;
      if (!mounted || myGeneration != _loadGeneration) return;
      final artistRows = artistRowsRaw.where((r) => r != null).map((r) => r!).toList();
      setState(() {
        _songs = songs;
        _artistRows = artistRows;
        _albums = albums;
        _failed = songs.isEmpty && artistRows.isEmpty && albums.isEmpty;
      });
    } catch (_) {
      if (mounted && myGeneration == _loadGeneration) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
        child: Center(
          child: Text(
            'Play a few songs and your suggestions will show up here',
            textAlign: TextAlign.center,
            style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13),
          ),
        ),
      );
    }
    final songs = _songs;
    final artistRows = _artistRows;
    final albums = _albums;
    if (songs == null || artistRows == null || albums == null) {
      return const Center(child: AurumMorphLoader(contained: true));
    }

    final seenArtistIds = <String>{};
    final uniqueArtists = <ArtistSimple>[];
    for (final row in artistRows) {
      for (final a in row.related) {
        if (seenArtistIds.add(a.id)) uniqueArtists.add(a);
      }
    }

    Widget heading(String text, double top) => Padding(
          padding: EdgeInsets.fromLTRB(20, top, 20, 8),
          child: Text(
            text,
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        );

    return CustomScrollView(
      key: const ValueKey('suggestions_landing'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
          if (songs.isNotEmpty) ...[
            SliverToBoxAdapter(child: heading('Unique Songs', 16)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final song = songs[i];
                  return SongTile(
                    key: ValueKey('unique_song_${song.id}'),
                    song: song,
                    queue: songs,
                    index: i,
                    showIndex: true,
                    displayIndex: i + 1,
                  );
                },
                childCount: songs.length,
              ),
            ),
          ],
          if (uniqueArtists.isNotEmpty) ...[
            SliverToBoxAdapter(child: heading('Unique Artists', 20)),
            SliverToBoxAdapter(child: FadedHorizontalList(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                cacheExtent: 500,
                itemCount: uniqueArtists.length,
                itemBuilder: (context, i) =>
                    _SuggestionArtistChip(key: ValueKey(uniqueArtists[i].id), artist: uniqueArtists[i]),
              ),
            )),
          ],
          if (albums.isNotEmpty) ...[
            SliverToBoxAdapter(child: heading('Top Albums', 20)),
            SliverToBoxAdapter(child: SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                cacheExtent: 500,
                itemCount: albums.length,
                itemBuilder: (context, i) => _AlbumCard(
                  key: ValueKey(albums[i].collectionId),
                  album: albums[i],
                  onTap: () {
                    AurumHaptics.light();
                    Navigator.push(
                      context,
                      AurumDepthRoute(
                        builder: (_) => AlbumScreen(
                          albumId: albums[i].collectionId,
                          albumName: albums[i].name,
                          artworkUrl: albums[i].artworkUrl,
                        ),
                      ),
                    );
                  },
                ),
              ),
            )),
          ],
          SliverToBoxAdapter(child: SizedBox(height: _searchBottomClearance(context))),
      ],
    );
  }
}

class _SuggestionArtistChip extends StatelessWidget {
  final ArtistSimple artist;
  const _SuggestionArtistChip({super.key, required this.artist});

  void _open(BuildContext context) {
    AurumHaptics.selection();
    AurumDepthRoute.to(
      context,
      ArtistScreen(
        artistId: artist.id.isNotEmpty ? artist.id : null,
        artistName: artist.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AurumPressable(
        scaleAmount: 0.94,
        onTap: () => _open(context),
        child: Container(
          width: 96,
          margin: const EdgeInsets.only(right: 14),
          child: Column(
            children: [
              AurumStackedArtwork(url: artist.imageUrl, size: 90, circular: true),
              const SizedBox(height: 8),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreMoodTile extends StatelessWidget {
  final String title;
  final Color color;
  final String? artworkUrl;
  final VoidCallback onTap;

  const _ExploreMoodTile({
    required this.title,
    required this.color,
    required this.onTap,
    this.artworkUrl,
  });

  @override
  Widget build(BuildContext context) {
    final art = artworkUrl;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (art != null && art.isNotEmpty) ...[
                const SizedBox(width: 10),
                Transform.rotate(
                  angle: 0.25,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      cacheManager: AurumImageCache(),
                      imageUrl: art,
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      memCacheWidth: 92,
                      memCacheHeight: 92,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

double _searchBottomClearance(BuildContext context) {
  final view = View.of(context);
  final systemBottom = view.padding.bottom / view.devicePixelRatio;
  return 68 + 8 + 64 + 10 + 16 + systemBottom;
}

class _KeyboardInsetPadding extends StatelessWidget {
  final Widget child;
  const _KeyboardInsetPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}

class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressScale({required this.child, required this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AurumMotion.durationOrZero(AurumMotion.short1),
      reverseDuration: AurumMotion.durationOrZero(AurumMotion.medium1),
    );
    _scale = Tween(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    AurumHaptics.selection();
    _ctrl.forward().then((_) {
      if (mounted) _ctrl.reverse();
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final BrowseAlbum album;
  final VoidCallback onTap;
  const _AlbumCard({super.key, required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                AurumArtwork(url: album.artworkUrl, size: 130),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(album.name, style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            album.trackCount != null && album.trackCount! > 1
                ? '${album.artist} • ${album.trackCount} songs'
                : album.artist,
            style: TextStyle(color: AurumTheme.textSecondaryOf(context), fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }
}

class _ArtistChip extends StatelessWidget {
  final BrowseArtist artist;
  final VoidCallback onTap;
  const _ArtistChip({required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AurumTheme.bgCardOf(context),
              border: Border.all(color: AurumTheme.accentOf(context).withOpacity(0.3), width: 1.5),
            ),
            child: ClipOval(
              child: artist.imageUrl.isEmpty
                  ? Icon(Icons.person_rounded, color: AurumTheme.accentOf(context).withOpacity(0.7), size: 28)
                  : AurumArtwork(url: artist.imageUrl, size: 60, borderRadius: 30),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 70,
            child: Text(artist.name, style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 11, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ),
        ]),
      ),
    );
  }
}
