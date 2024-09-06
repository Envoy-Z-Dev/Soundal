import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:mutex/mutex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:queue/queue.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:soundal/Helpers/config.dart';
import 'package:soundal/Helpers/countrycodes.dart';
import 'package:soundal/Helpers/handle_native.dart';
import 'package:soundal/Helpers/import_export_playlist.dart';
import 'package:soundal/Helpers/logging.dart';
import 'package:soundal/Helpers/route_handler.dart';
import 'package:soundal/Screens/About/about.dart';
import 'package:soundal/Screens/Home/home.dart';
import 'package:soundal/Screens/Library/downloads.dart';
import 'package:soundal/Screens/Library/playlists.dart';
import 'package:soundal/Screens/Library/recent.dart';
import 'package:soundal/Screens/Library/stats.dart';
import 'package:soundal/Screens/Login/auth.dart';
import 'package:soundal/Screens/Login/pref.dart';
import 'package:soundal/Screens/Player/audioplayer.dart';
import 'package:soundal/Screens/Settings/setting.dart';
import 'package:soundal/Services/audio_service.dart';
import 'package:soundal/theme/app_theme.dart';

final PageController _pageController = PageController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //Paint.enableDithering = true;

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await Hive.initFlutter('Soundal');
  } else {
    await Hive.initFlutter();
  }
  await openHiveBox('settings');
  await openHiveBox('downloads');
  await openHiveBox('stats');
  await openHiveBox('Favorite Songs');
  await openHiveBox('cache', limit: true);
  await openHiveBox('ytlinkcache', limit: true);
  await openHiveBox('spoty2youtube', limit: true);
  if (Platform.isAndroid) {
    setOptimalDisplayMode();
  }
  await startService();
  MyApp.temporaryPath = (await getTemporaryDirectory()).path;
  runApp(MyApp());
}

Future<void> setOptimalDisplayMode() async {
  await FlutterDisplayMode.setHighRefreshRate();
  // final List<DisplayMode> supported = await FlutterDisplayMode.supported;
  // final DisplayMode active = await FlutterDisplayMode.active;

  // final List<DisplayMode> sameResolution = supported
  //     .where(
  //       (DisplayMode m) => m.width == active.width && m.height == active.height,
  //     )
  //     .toList()
  //   ..sort(
  //     (DisplayMode a, DisplayMode b) => b.refreshRate.compareTo(a.refreshRate),
  //   );

  // final DisplayMode mostOptimalMode =
  //     sameResolution.isNotEmpty ? sameResolution.first : active;

  // await FlutterDisplayMode.setPreferredMode(mostOptimalMode);
}

Future<void> startService() async {
  await initializeLogging();
  MetadataGod.initialize();
  final AudioPlayerHandler audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandlerImpl(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.arojas.soundal.channel.audio',
      androidNotificationChannelName: 'Soundal',
      androidNotificationIcon: 'drawable/ic_stat_music_note',
      androidShowNotificationBadge: true,
      //androidStopForegroundOnPause: true,

      // Hive.box('settings').get('stopServiceOnPause', defaultValue: true) as bool,
      //notificationColor: Colors.grey[900],
    ),
  );
  GetIt.I.registerSingleton<AudioPlayerHandler>(audioHandler);
  GetIt.I.registerSingleton<MyTheme>(MyTheme());
}

Future<void> openHiveBox(String boxName, {bool limit = false}) async {
  final box = await Hive.openBox(boxName).onError((error, stackTrace) async {
    Logger.root.severe('Failed to open $boxName Box', error, stackTrace);
    final Directory dir = await getApplicationDocumentsDirectory();
    final String dirPath = dir.path;
    File dbFile = File('$dirPath/$boxName.hive');
    File lockFile = File('$dirPath/$boxName.lock');
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      dbFile = File('$dirPath/Soundal/$boxName.hive');
      lockFile = File('$dirPath/Soundal/$boxName.lock');
    }
    await dbFile.delete();
    await lockFile.delete();
    await Hive.openBox(boxName);
    throw 'Failed to open $boxName Box\nError: $error';
  });
  // clear box if it grows large
  if (limit && box.length > 500) {
    box.clear();
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();

  static final Mutex hiveMutex = Mutex();
  static late String temporaryPath;
  static final spotifyQueue = Queue(delay: const Duration(milliseconds: 350));

  // ignore: unreachable_from_main
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class _MyAppState extends State<MyApp> {
  Locale _locale = const Locale('en', '');
  late StreamSubscription _intentTextStreamSubscription;
  late StreamSubscription _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _intentTextStreamSubscription.cancel();
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final String systemLangCode = Platform.localeName.substring(0, 2);
    /*if (ConstantCodes.languageCodes.values.contains(systemLangCode)) {
      _locale = Locale(systemLangCode);
    } else {*/
    final String lang =
        Hive.box('settings').get('lang', defaultValue: 'English') as String;
    _locale = Locale(ConstantCodes.languageCodes[lang] ?? 'en');
    //}

    AppTheme.currentTheme.addListener(() {
      setState(() {});
    });

    if (Platform.isAndroid || Platform.isIOS) {
      // For sharing or opening urls/text coming from outside the app while the app is in the memory
      _intentTextStreamSubscription =
          ReceiveSharingIntent.getTextStream().listen(
        (String value) {
          Logger.root.info('Received intent on stream: $value');
          handleSharedText(value, navigatorKey);
        },
        onError: (err) {
          Logger.root.severe('ERROR in getTextStream', err);
        },
      );

      // For sharing or opening urls/text coming from outside the app while the app is closed
      ReceiveSharingIntent.getInitialText().then(
        (String? value) {
          Logger.root.info('Received Intent initially: $value');
          if (value != null) handleSharedText(value, navigatorKey);
        },
        onError: (err) {
          Logger.root.severe('ERROR in getInitialTextStream', err);
        },
      );

      // For sharing files coming from outside the app while the app is in the memory
      _intentDataStreamSubscription =
          ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
          if (value.isNotEmpty) {
            for (final file in value) {
              if (file.path.endsWith('.json')) {
                final List playlistNames = Hive.box('settings')
                        .get('playlistNames')
                        ?.toList() as List? ??
                    ['Favorite Songs'];
                importFilePlaylist(
                  null,
                  playlistNames,
                  path: file.path,
                  pickFile: false,
                ).then(
                  (value) => navigatorKey.currentState?.pushNamed('/playlists'),
                );
              }
            }
          }
        },
        onError: (err) {
          Logger.root.severe('ERROR in getDataStream', err);
        },
      );

      // For sharing files coming from outside the app while the app is closed
      ReceiveSharingIntent.instance.getInitialMedia().then(
        (List<SharedMediaFile> value) {
          if (value.isNotEmpty) {
            for (final file in value) {
              if (file.path.endsWith('.json')) {
                final List playlistNames = Hive.box('settings')
                        .get('playlistNames')
                        ?.toList() as List? ??
                    ['Favorite Songs'];
                importFilePlaylist(
                  null,
                  playlistNames,
                  path: file.path,
                  pickFile: false,
                ).then(
                  (value) => navigatorKey.currentState?.pushNamed('/playlists'),
                );
              }
            }
          }
        },
        onError: (err) {
          Logger.root.severe('ERROR in getDataStream', err);
        },
      );

      // For sharing files coming from outside the app while the app is closed
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          for (final file in value) {
            if (file.path.endsWith('.json')) {
              final List playlistNames = Hive.box('settings')
                      .get('playlistNames')
                      ?.toList() as List? ??
                  ['Favorite Songs'];
              importFilePlaylist(
                null,
                playlistNames,
                path: file.path,
                pickFile: false,
              ).then(
                (value) => navigatorKey.currentState?.pushNamed('/playlists'),
              );
            }
          }
        }
      });

      final MyTheme currentTheme = GetIt.I<MyTheme>();
      currentTheme.switchTheme(
        useSystemTheme: false,
        isDark: true,
      );

      //Use amoled theme by default
      Hive.box('settings').put('darkMode', true);

      Hive.box('settings').put('backGrad', 4);
      currentTheme.backGrad = 4;
      Hive.box('settings').put('cardGrad', 6);
      currentTheme.cardGrad = 6;
      Hive.box('settings').put('bottomGrad', 4);
      currentTheme.bottomGrad = 4;

      currentTheme.switchCanvasColor('Black');
      currentTheme.switchCardColor('Grey900');
    }
  }

  void setLocale(Locale value) {
    setState(() {
      _locale = value;
    });
  }

  Widget initialFuntion() {
    return Hive.box('settings').get('userId') != null
        ? HomePage(pageController: _pageController)
        : AuthScreen();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return MaterialApp(
      title: 'Soundal',
      restorationScopeId: 'soundal',
      debugShowCheckedModeBanner: false,
      themeMode: AppTheme.themeMode,
      theme: AppTheme.lightTheme(
        context: context,
      ),
      darkTheme: AppTheme.darkTheme(
        context: context,
      ),
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: ConstantCodes.languageCodes.entries
          .map((languageCode) => Locale(languageCode.value, ''))
          .toList(),
      routes: {
        '/': (context) => initialFuntion(),
        '/pref': (context) => const PrefScreen(),
        '/setting': (context) => const SettingPage(),
        '/about': (context) => AboutScreen(),
        '/playlists': (context) => PlaylistScreen(),
        //'/nowplaying': (context) => NowPlaying(),
        '/recent': (context) => RecentlyPlayed(),
        '/downloads': (context) => const Downloads(),
        '/stats': (context) => const Stats(),
      },
      navigatorKey: navigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        if (!GetIt.I.isRegistered<PlayScreen>()) {
          const playScreen = PlayScreen();
          GetIt.I.registerSingleton<PlayScreen>(playScreen);
        }

        if (settings.name == '/player') {
          return PageRouteBuilder(
            opaque: false,
            pageBuilder: (_, __, ___) => GetIt.I<PlayScreen>(),
          );
        }
        return HandleRoute.handleRoute(settings.name);
      },
    );
  }
}
