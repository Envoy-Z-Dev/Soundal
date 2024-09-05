import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/CustomWidgets/custom_physics.dart';
import 'package:soundal/CustomWidgets/download_button.dart';
import 'package:soundal/CustomWidgets/empty_screen.dart';
import 'package:soundal/CustomWidgets/like_button.dart';
import 'package:soundal/CustomWidgets/song_tile_trailing_menu.dart';
import 'package:soundal/Helpers/countrycodes.dart';
import 'package:soundal/Helpers/format.dart';
import 'package:soundal/Helpers/logger.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/Screens/Settings/setting.dart';
import 'package:soundal/Services/player_service.dart';
import 'package:soundal/Services/yt_music.dart';
import 'package:url_launcher/url_launcher.dart';

List localSongs = [];
List globalSongs = [];
bool localFetched = false;
bool globalFetched = false;
final ValueNotifier<bool> localFetchFinished = ValueNotifier<bool>(false);
final ValueNotifier<bool> globalFetchFinished = ValueNotifier<bool>(false);

class TopCharts extends StatefulWidget {
  final PageController pageController;
  const TopCharts({super.key, required this.pageController});

  @override
  _TopChartsState createState() => _TopChartsState();
}

class _TopChartsState extends State<TopCharts>
    with AutomaticKeepAliveClientMixin<TopCharts> {
  final ValueNotifier<bool> localFetchFinished = ValueNotifier<bool>(false);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext cntxt) {
    super.build(context);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool rotated = MediaQuery.of(context).size.height < screenWidth;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: IconButton(
                icon: const Icon(Icons.my_location_rounded),
                onPressed: () async {
                  await SpotifyCountry().changeCountry(context: context);
                },
              ),
            ),
          ],
          bottom: TabBar(
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(
                child: Text(
                  AppLocalizations.of(context)!.local,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                ),
              ),
              Tab(
                child: Text(
                  AppLocalizations.of(context)!.global,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            AppLocalizations.of(context)!.spotifyCharts,
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: NotificationListener(
          onNotification: (overscroll) {
            if (overscroll is OverscrollNotification &&
                overscroll.overscroll != 0 &&
                overscroll.dragDetails != null) {
              widget.pageController.animateToPage(
                overscroll.overscroll < 0 ? 0 : 2,
                curve: Curves.ease,
                duration: const Duration(milliseconds: 150),
              );
            }
            return true;
          },
          child: TabBarView(
            physics: const CustomPhysics(),
            children: [
              ValueListenableBuilder(
                valueListenable: Hive.box('settings').listenable(),
                builder: (BuildContext context, Box box, Widget? widget) {
                  return TopPage(
                    type: box.get('region', defaultValue: 'Global').toString(),
                  );
                },
              ),
              // TopPage(type: 'local'),
              const TopPage(type: 'Global'),
            ],
          ),
        ),
      ),
    );
  }
}

Future<List> getChartDetails(String accessToken, String type) async {
  final String globalPlaylistId = ConstantCodes.localChartCodes['Global']!;
  final String localPlaylistId = ConstantCodes.localChartCodes.containsKey(type)
      ? ConstantCodes.localChartCodes[type]!
      : ConstantCodes.localChartCodes['Global']!;
  final String playlistId =
      type == 'Global' ? globalPlaylistId : localPlaylistId;
  final List data = [];
  List songList = [];

  final List playlistCache = Hive.box('cache').get(
    'spotifyPlaylists',
    defaultValue: [],
  ) as List;

  var playlistCached = playlistCache.firstWhere(
    (element) => element['id'] == playlistId,
    orElse: () => null,
  );

  if (playlistCached == null) {
    await callSpotifyFunction(
      function: (String accessToken) async => {
        playlistCached = await SpotifyApi().getPlaylist(
          accessToken,
          playlistId,
        ),
      },
    );
    playlistCache.add(playlistCached);
    playlistCached = playlistCache.firstWhere(
      (element) => element['id'] == playlistId,
      orElse: () => null,
    );
  }

  if ((playlistCached['tracks'] as List).firstOrNull?['is_local'] != null) {
    Logger.root.info(
      'No cached songs for $playlistId, update cache to add songs',
    );

    if (playlistCached != null &&
        playlistCached['tracks']?.runtimeType != List) {
      await callSpotifyFunction(
        function: (String accessToken) async => {
          playlistCached['tracks'] = await SpotifyApi().getAllTracksOfPlaylist(
            accessToken,
            playlistId,
          ),
        },
      );
    }

    for (final element in playlistCached['tracks'] as List) {
      data.add(element['track']);
    }

    songList = await FormatResponse.parallelSpotifyListToYoutubeList(
      data,
    );

    playlistCached['tracks'] = songList;
    Hive.box('cache').put('spotifyPlaylists', playlistCache);
  } else {
    songList = playlistCached['tracks'] as List;
  }

  return songList;
}

Future<void> scrapData(String type, {bool signIn = false}) async {
  final bool spotifySigned =
      Hive.box('settings').get('spotifySigned', defaultValue: false) as bool;

  if (!spotifySigned && !signIn) {
    return;
  }
  final String? accessToken = await retriveAccessToken();
  if (accessToken == null) {
    launchUrl(
      Uri.parse(
        SpotifyApi().requestAuthorization(),
      ),
      mode: LaunchMode.externalApplication,
    );
    final appLinks = AppLinks();
    appLinks.allUriLinkStream.listen(
      (uri) async {
        final link = uri.toString();
        if (link.contains('code=')) {
          final code = link.split('code=')[1];
          await Hive.box('settings').put('spotifyAppCode', code);
          final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
          final List<String> data =
              await SpotifyApi().getAccessToken(code: code);
          if (data.isNotEmpty) {
            await Hive.box('settings').put('spotifyAccessToken', data[0]);
            await Hive.box('settings').put('spotifyRefreshToken', data[1]);
            await Hive.box('settings').put('spotifySigned', true);
            await Hive.box('settings')
                .put('spotifyTokenExpireAt', currentTime + int.parse(data[2]));
          }

          final temp = await getChartDetails(data[0], type);
          if (temp.isNotEmpty) {
            await Hive.box('cache').put('${type}_chart', temp);
            if (type == 'Global') {
              globalSongs = temp;
            } else {
              localSongs = temp;
            }
          }
          if (type == 'Global') {
            globalFetchFinished.value = true;
          } else {
            localFetchFinished.value = true;
          }
        }
      },
    );
  } else {
    final temp = await getChartDetails(accessToken, type);
    if (temp.isNotEmpty) {
      await Hive.box('cache').put('${type}_chart', temp);
      if (type == 'Global') {
        globalSongs = temp;
      } else {
        localSongs = temp;
      }
    }
    if (type == 'Global') {
      globalFetchFinished.value = true;
    } else {
      localFetchFinished.value = true;
    }
  }
}

class TopPage extends StatefulWidget {
  final String type;
  const TopPage({super.key, required this.type});
  @override
  _TopPageState createState() => _TopPageState();
}

class _TopPageState extends State<TopPage>
    with AutomaticKeepAliveClientMixin<TopPage> {
  Future<void> getCachedData(String type) async {
    if (type == 'Global') {
      globalFetched = true;
    } else {
      localFetched = true;
    }
    if (type == 'Global') {
      globalSongs = await Hive.box('cache')
          .get('${type}_chart', defaultValue: []) as List;
    } else {
      localSongs = await Hive.box('cache')
          .get('${type}_chart', defaultValue: []) as List;
    }
    setState(() {});
  }

  YtMusicService ytMusic = YtMusicService();

  @override
  bool get wantKeepAlive => true;


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool isGlobal = widget.type == 'Global';
    if ((isGlobal && !globalFetched) || (!isGlobal && !localFetched)) {
      ytMusic.init().then((value) {
        getCachedData(widget.type);
        scrapData(widget.type);
      });
    }
    return ValueListenableBuilder(
      valueListenable: isGlobal ? globalFetchFinished : localFetchFinished,
      builder: (BuildContext context, bool value, Widget? child) {
        final List showList = isGlobal ? globalSongs : localSongs;
        return Column(
          children: [
            if (!(Hive.box('settings').get('spotifySigned', defaultValue: false)
                as bool))
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      scrapData(widget.type, signIn: true);
                    },
                    child: Text(AppLocalizations.of(context)!.signInSpotify),
                  ),
                ),
              )
            else if (showList.isEmpty)
              Expanded(
                child: value
                    ? emptyScreen(
                        context,
                        0,
                        ':( ',
                        100,
                        'ERROR',
                        60,
                        'Service Unavailable',
                        20,
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                        ],
                      ),
              )
            else
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: showList.length,
                  itemExtent: 70.0,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: Card(
                        margin: EdgeInsets.zero,
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7.0),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            const Image(
                              image: AssetImage('assets/cover.jpg'),
                            ),
                            if (showList[index]['image'] != '')
                              CachedNetworkImage(
                                fit: BoxFit.cover,
                                imageUrl: showList[index]['image'].toString(),
                                errorWidget: (context, _, __) => const Image(
                                  fit: BoxFit.cover,
                                  image: AssetImage('assets/cover.jpg'),
                                ),
                                placeholder: (context, url) => const Image(
                                  fit: BoxFit.cover,
                                  image: AssetImage('assets/cover.jpg'),
                                ),
                              ),
                          ],
                        ),
                      ),
                      title: Text(
                        '${index + 1}. ${showList[index]["title"]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        showList[index]['artist'].toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DownloadButton(
                            data: showList[index] as Map,
                            icon: 'download',
                          ),
                          LikeButton(
                            mediaItem: null,
                            data: showList[index] as Map,
                          ),
                          SongTileTrailingMenu(data: showList[index] as Map),
                        ],
                      ),
                      onTap: () {
                        PlayerInvoke.init(
                          songsList: showList,
                          index: index,
                          isOffline: false,
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
