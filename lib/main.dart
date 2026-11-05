// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'services/analytics_service.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/diagnostic_log_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/native_engine_bridge.dart';
import 'services/voice_play_service.dart';
import 'services/notification_service.dart';
import 'services/update_push_service.dart';
import 'services/update_service.dart';
import 'services/api_service.dart';
import 'services/share_card_service.dart';
import 'services/home_feed_cache.dart';
import 'services/recommendation_engine.dart';
import 'services/auth_service.dart';
import 'services/audio_prefs.dart';
import 'services/battery_saver_controller.dart';
import 'services/data_saver_controller.dart';
import 'providers/player_provider.dart';
import 'providers/library_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/download_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/followed_artists_provider.dart';
import 'providers/followed_albums_provider.dart';
import 'providers/saved_mixes_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/premium_provider.dart';
import 'theme/aurum_theme.dart';
import 'screens/main_shell.dart';
import 'screens/jam_screen.dart';
import 'services/jam_service.dart';
import 'package:app_links/app_links.dart';
import 'screens/link_tv_screen.dart';
import 'screens/library_screen.dart';
import 'providers/source_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/recently_played_provider.dart';
import 'screens/app_lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/aurum_transitions.dart';
import 'utils/aurum_haptics.dart';
import 'utils/aurum_motion.dart';

late NativeAudioEngine _audioEngine;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final RouteObserver<ModalRoute<void>> aurumRouteObserver =
    RouteObserver<ModalRoute<void>>();

Widget aurumDebugErrorWidgetBuilder(FlutterErrorDetails details) {
  if (kReleaseMode) return const SizedBox.shrink();
  return Material(
    color: const Color(0xFF7A0000),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          details.exceptionAsString(),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    ),
  );
}

Future<void> main() async {
  runZonedGuarded(() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = aurumDebugErrorWidgetBuilder;

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    DiagnosticLogService.logNetworkError(
      'flutter_error',
      details.exceptionAsString(),
    );
    previousOnError?.call(details);
  };

  ApiService.wakeSaavn();

  final hiveFuture = Hive.initFlutter();

  final authFuture = () async {
    try {
      await AuthService.init();
    } catch (_) {}
  }();

  await Future.wait<void>([hiveFuture, authFuture]);

  try {
    await AudioPrefs.primeDataSaverEarly();
  } catch (_) {}

  await ThemeProvider.primeEarly();

  runApp(AurumApp(engine: _audioEngine = NativeAudioEngine()));

  unawaited(_prefetchHomeFeed());

  unawaited(_restoreAudioEffects());

  try {
    final prefs = await SharedPreferences.getInstance();
    final maxImgMB = prefs.getDouble('max_image_cache') ?? 100.0;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        (maxImgMB * 1024 * 1024).toInt();
    PaintingBinding.instance.imageCache.maximumSize = 250;
  } catch (_) {}

  final hapticsFuture = () async {
    try {
      await AurumHaptics.init();
    } catch (_) {}
  }();
  final orientationFuture = () async {
    try {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } catch (_) {}
  }();

  try {
    await Future.wait<void>([hapticsFuture, orientationFuture, AudioPrefs.load()]);
  } catch (_) {}

  try {
    BatterySaverController.instance.start();
  } catch (_) {}

  try {
    DataSaverController.instance.start();
  } catch (_) {}

  unawaited(VoicePlayService.init());
  unawaited(_askNotificationOnce(afterDelay: const Duration(seconds: 20)));

  try {
    await NotificationService.instance.init();
    NotificationService.instance.onNotificationTapped = () {
      navigatorKey.currentState?.push(
        AurumPageRoute(builder: (_) => const DownloadsScreen()),
      );
    };
    NotificationService.instance.onUpdateNotificationTapped = () {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) UpdateService.checkForUpdate(ctx, silent: false, force: true);
    };
    NotificationService.instance.onJamNotificationTapped = () {
      navigatorKey.currentState?.push(
        AurumPageRoute(builder: (_) => const JamScreen()),
      );
    };
  } catch (_) {}

  try {
    await AnalyticsService.instance.init();
  } catch (_) {}
  try {
    await UpdatePushService.instance.init();
  } catch (_) {}

  try {
    AppLinks().uriLinkStream.listen(_onJamLink, onError: (_) {});
  } catch (_) {}

  try {
    UpdateService.wireInstallResultHandler();
  } catch (_) {}
  }, (error, stack) {
    debugPrint('[Aurum] Uncaught error: $error\n$stack');
    DiagnosticLogService.logNetworkError('uncaught_zone_error', '$error');
  });
}

bool _jamFirstLink = true;
String? _jamLastLink;
int _jamLastLinkAt = 0;

void _onJamLink(Uri uri) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final key = uri.toString();
  if (_jamLastLink == key && now - _jamLastLinkAt < 5000) return;
  _jamLastLink = key;
  _jamLastLinkAt = now;
  final cold = _jamFirstLink;
  _jamFirstLink = false;
  if (cold) {
    Future.delayed(const Duration(milliseconds: 1800), () => _handleJamLink(uri));
  } else {
    _handleJamLink(uri);
  }
}

void _handleJamLink(Uri uri) {
  try {
    String? tvRaw;
    if (uri.scheme == 'astra' && uri.host == 'tv' && uri.pathSegments.isNotEmpty) {
      tvRaw = uri.pathSegments.first;
    } else if (uri.host == 'astra.mmusic.workers.dev' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'tv') {
      tvRaw = uri.pathSegments[1];
    }
    if (tvRaw != null) {
      navigatorKey.currentState?.push(
        AurumPageRoute(builder: (_) => LinkTvScreen(initialCode: tvRaw)),
      );
      return;
    }
    String? songSrc, songId;
    if (uri.scheme == 'astra' && uri.host == 'song' && uri.pathSegments.length >= 2) {
      songSrc = uri.pathSegments[0];
      songId = uri.pathSegments[1];
    } else if (uri.host == 'astra.mmusic.workers.dev' &&
        uri.pathSegments.length >= 3 &&
        uri.pathSegments.first == 's') {
      songSrc = uri.pathSegments[1];
      songId = uri.pathSegments[2];
    }
    if (songSrc != null && songId != null) {
      final d = uri.queryParameters['d'];
      final meta = d == null ? null : ShareCardService.decodeMeta(d);
      _playSharedSong(songSrc, songId, meta?.title ?? '', meta?.artist ?? '');
      return;
    }
    String? raw;
    if (uri.scheme == 'astra' && uri.host == 'jam' && uri.pathSegments.isNotEmpty) {
      raw = uri.pathSegments.first;
    } else if (uri.host == 'astra.mmusic.workers.dev' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'jam') {
      raw = uri.pathSegments[1];
    }
    final code = raw == null ? null : JamService.parseCode(raw);
    if (code == null) return;
    navigatorKey.currentState?.push(
      AurumPageRoute(builder: (_) => JamScreen(initialCode: code)),
    );
  } catch (_) {}
}

Future<void> _playSharedSong(String src, String id, String title, String artist) async {
  try {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final player = Provider.of<PlayerProvider>(ctx, listen: false);
    final q = ('$title $artist').trim();
    if (q.isEmpty) return;
    final results = src == 'yt'
        ? await ApiService.searchYtRaw(q, limit: 10)
        : await ApiService.searchSaavnRaw(q, limit: 10);
    if (results.isEmpty) return;
    final song = results.firstWhere(
      (s) => s.id == id,
      orElse: () => results.firstWhere(
        (s) => s.title.toLowerCase() == title.toLowerCase(),
        orElse: () => results.first,
      ),
    );
    await player.playSong(song, queue: [song], index: 0);
  } catch (_) {}
}

class AurumApp extends StatelessWidget {
  final NativeAudioEngine engine;
  const AurumApp({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final sp = SourceProvider();
            sp.init();
            return sp;
          },
        ),
        ChangeNotifierProvider(create: (_) => RecentlyPlayedProvider()..init()),
        ChangeNotifierProvider(create: (_) => DownloadProvider(engine)..init()),
        ChangeNotifierProxyProvider<DownloadProvider, FavoritesProvider>(
          create: (_) => FavoritesProvider()..init(),
          update: (_, dl, fav) {
            fav?.downloadProvider = dl;
            return fav ?? (FavoritesProvider()..init()..downloadProvider = dl);
          },
        ),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()..init()),
        ChangeNotifierProvider(create: (_) => FollowedArtistsProvider()..init()),
        ChangeNotifierProvider(create: (_) => FollowedAlbumsProvider()..init()),
        ChangeNotifierProvider(create: (_) => SavedMixesProvider()..init()),
        ChangeNotifierProvider(
          create: (_) {
            final auth = AuthProvider();
            auth.init();
            AudioPrefs.isSignedIn = auth.isSignedIn;
            auth.addListener(() => AudioPrefs.isSignedIn = auth.isSignedIn);
            return auth;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final pp = PremiumProvider();
            pp.onSlowNetwork = () {
              scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(
                  content: const Text('Please check your internet connection'),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            };
            pp.init();
            pp.addListener(() => AudioPrefs.isPremium = pp.isPremium);
            return pp;
          },
        ),
        ChangeNotifierProxyProvider2<RecentlyPlayedProvider, FavoritesProvider, PlayerProvider>(
          create: (context) {
            final p = PlayerProvider(engine);
            context.read<SourceProvider>().isCurrentSongLocal =
                () => p.currentSong?.isLocal ?? false;
            context.read<SourceProvider>().hasPlaybackBuffer =
                () => p.hasPlaybackBuffer;
            context.read<SourceProvider>().onReconnected = () {
              p.resumeAfterReconnect();
              scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        "You're back online",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF1DB954),
                  duration: const Duration(seconds: 2, milliseconds: 500),
                  behavior: SnackBarBehavior.floating,
                  elevation: 6,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              );
            };
            context.read<SourceProvider>().onSourceChanged = () {
              p.markInterruptedByNetworkLoss();
              engine.stop().catchError((e, st) {
                debugPrint('[Aurum] stop() on source change failed: $e');
              });
              scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(
                  content: const Text("You're offline — playback paused"),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            };
            p.onResolveTakingLong = () {
              scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(
                  content: const Text('Please check your internet connection'),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            };
            return p;
          },
          update: (_, recentlyPlayed, favorites, player) {
            final p = player ?? PlayerProvider(engine, recentlyPlayedProvider: recentlyPlayed);
            p.updateRecentlyPlayed(recentlyPlayed);
            p.updateFavorites(favorites);
            return p;
          },
        ),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer2<ThemeProvider, LocaleProvider>(
            builder: (context, themeProvider, localeProvider, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            themeProvider.updateDynamicSchemes(lightDynamic, darkDynamic);
          });

          final isDark = themeProvider.isDarkOf(context);

          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ));

          final preset = themeProvider.effectivePreset;
          final baseLight = (themeProvider.isDynamic && lightDynamic != null)
              ? AurumTheme.dynamicTheme(lightDynamic)
              : (preset != AurumColorPreset.none
                  ? AurumTheme.presetTheme(preset, brightness: Brightness.light)
                  : AurumTheme.lightTheme);
          final baseDark = (themeProvider.isDynamic && darkDynamic != null)
              ? AurumTheme.dynamicTheme(darkDynamic)
              : (themeProvider.isAmoled
                  ? (preset != AurumColorPreset.none
                      ? AurumTheme.amoledPresetTheme(preset)
                      : AurumTheme.amoledTheme)
                  : (preset != AurumColorPreset.none
                      ? AurumTheme.presetTheme(preset)
                      : AurumTheme.darkTheme));

          final resolvedFamily = themeProvider.resolvedFontFamily;
          final resolvedFallback = themeProvider.resolvedFontFamilyFallback;

          var lightTextTheme = themeProvider.resolvedTextTheme(baseLight.textTheme);
          var darkTextTheme = themeProvider.resolvedTextTheme(baseDark.textTheme);
          if (resolvedFamily != null) {
            lightTextTheme = lightTextTheme.apply(
                fontFamily: resolvedFamily, fontFamilyFallback: resolvedFallback);
            darkTextTheme = darkTextTheme.apply(
                fontFamily: resolvedFamily, fontFamilyFallback: resolvedFallback);
          }

          final lightTheme = baseLight.copyWith(textTheme: lightTextTheme);
          final darkTheme = baseDark.copyWith(textTheme: darkTextTheme);

          return MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            title: 'Astra Music',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.themeMode,
            theme: lightTheme,
            darkTheme: darkTheme,
            navigatorObservers: [aurumRouteObserver],
            locale: localeProvider.locale,
            supportedLocales: kSupportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            localeResolutionCallback: (deviceLocale, supported) {
              if (deviceLocale != null) {
                for (final l in supported) {
                  if (l.languageCode == deviceLocale.languageCode) return l;
                }
              }
              return const Locale('en');
            },
            builder: (context, child) {
              return AnimatedTheme(
                data: Theme.of(context),
                duration: AurumMotion.durationOrZero(AurumMotion.long1),
                curve: AurumMotion.standard,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: SplashScreen(
              child: _BlurShaderWarmup(
                child: AppLockScreen(
                  child: const _OnboardingGate(child: MainShell()),
                ),
              ),
            ),
            );
            },
          );
        },
      ),
    );
  }
}

class _OnboardingGate extends StatefulWidget {
  final Widget child;
  const _OnboardingGate({required this.child});

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool? _done;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    bool done = true;
    try {
      final p = await SharedPreferences.getInstance();
      done = p.getBool('onboarding_complete') ?? false;
    } catch (_) {}
    if (mounted) setState(() => _done = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) {
      return const Scaffold(backgroundColor: AurumTheme.darkBg);
    }
    if (_done == false) {
      return OnboardingScreen(
        onDone: () {
          setState(() => _done = true);
          unawaited(_askNotificationOnce(
              afterDelay: const Duration(seconds: 2), force: true));
        },
      );
    }
    return widget.child;
  }
}

class _BlurShaderWarmup extends StatefulWidget {
  final Widget child;
  const _BlurShaderWarmup({required this.child});

  @override
  State<_BlurShaderWarmup> createState() => _BlurShaderWarmupState();
}

class _BlurShaderWarmupState extends State<_BlurShaderWarmup> {
  static bool _warmed = false;

  late bool _showWarmup;

  @override
  void initState() {
    super.initState();
    _showWarmup = !_warmed;
    _warmed = true;
    if (_showWarmup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _showWarmup = false);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_showWarmup)
          Positioned(
          left: -100,
          top: -100,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: const SizedBox(width: 4, height: 4),
                  ),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 4,
                      height: 4,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _restoreAudioEffects() async {
  try {
    final p = await SharedPreferences.getInstance();
    final premium = p.getBool('premium_sound') ?? false;
    final bass = p.getBool('bass_boost') ?? false;
    final norm = p.getBool('volume_normalization') ?? false;
    final bands = List.generate(10, (i) => p.getDouble('eq_band_$i') ?? 0.0);
    final customCurve = bands.any((g) => g != 0.0);
    if (bass || norm || customCurve) {
      await _audioEngine.applyAudioEffects(
        bassBoost: bass,
        volumeNormalization: norm,
        bandGainsDb: bands,
      );
    }
    if (premium) {
      await _audioEngine.applyPremiumSound(true);
    }
  } catch (_) {
  }
}

Future<void> _prefetchHomeFeed() async {
  try {
    if (await HomeFeedCache.isHomeShelvesFresh()) return;
    await RecommendationEngine.load();
    final shelves = await ApiService.fetchHomeShelvesForDisplay();
    if (shelves.isNotEmpty) {
      await HomeFeedCache.saveHomeShelves(shelves);
    }
  } catch (_) {}
}

Future<void> _askNotificationOnce({
  required Duration afterDelay,
  bool force = false,
}) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('notif_prompted_v1') ?? false) return;
    if (!force && !(p.getBool('onboarding_complete') ?? false)) return;
    await Future<void>.delayed(afterDelay);
    await p.setBool('notif_prompted_v1', true);
    await Permission.notification.request();
  } catch (_) {}
}
