import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:soundal/APIs/api.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/CustomWidgets/collage.dart';
import 'package:soundal/CustomWidgets/horizontal_albumlist.dart';
import 'package:soundal/CustomWidgets/horizontal_albumlist_separated.dart';
import 'package:soundal/CustomWidgets/like_button.dart';
import 'package:soundal/CustomWidgets/on_hover.dart';
import 'package:soundal/CustomWidgets/snackbar.dart';
import 'package:soundal/CustomWidgets/song_tile_trailing_menu.dart';
import 'package:soundal/Helpers/countrycodes.dart';
import 'package:soundal/Helpers/extensions.dart';
import 'package:soundal/Helpers/image_resolution_modifier.dart';
import 'package:soundal/Helpers/logger.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/Screens/Common/song_list.dart';
import 'package:soundal/Screens/Library/liked.dart';
import 'package:soundal/Screens/Search/artists.dart';
import 'package:soundal/Services/player_service.dart';

bool fetched = false;
String spotifyCountry = ConstantCodes.countryCodes[Hive.box('settings')
        .get('region', defaultValue: ['United States']).toString()]
    .toString()
    .toUpperCase();
List preferredLanguage = Hive.box('settings')
    .get('preferredLanguage', defaultValue: ['English']) as List;
List likedRadio =
    Hive.box('settings').get('likedRadio', defaultValue: []) as List;
Map data = Hive.box('cache').get('homepage', defaultValue: {}) as Map;
List lists = ['recent', 'playlist', ...data['collections'] as List];

class SpotifyHomePage extends StatefulWidget {
  @override
  _SpotifyHomePageState createState() => _SpotifyHomePageState();
}

class _SpotifyHomePageState extends State<SpotifyHomePage>
    with AutomaticKeepAliveClientMixin<SpotifyHomePage> {
  List recentList =
      Hive.box('cache').get('recentSongs', defaultValue: []) as List;
  Map likedArtists =
      Hive.box('settings').get('likedArtists', defaultValue: {}) as Map;
  List blacklistedHomeSections = Hive.box('settings')
      .get('blacklistedHomeSections', defaultValue: []) as List;
  List playlistNames =
      Hive.box('settings').get('playlistNames')?.toList() as List? ??
          ['Favorite Songs'];
  Map playlistDetails =
      Hive.box('settings').get('playlistDetails', defaultValue: {}) as Map;
  List playlistCache = Hive.box('cache').get(
    'spotifyPlaylists',
    defaultValue: [],
  ) as List;
  int recentIndex = 0;
  int playlistIndex = 1;

  Future<void> getHomePageData() async {
    Map receivedData = {};
    await callSpotifyFunction(
      function: (String accessToken) async => {
        receivedData =
            await SpotifyApi().fetchHomePageData(accessToken, spotifyCountry),
      },
    );

    if ((receivedData['collections'] as List).isNotEmpty) {
      Hive.box('cache').put('homepage', receivedData);
      data = receivedData;
      lists = ['recent', 'playlist', ...data['collections'] as List];
      lists.insert((lists.length / 2).round(), 'likedArtists');
    } else {
      Logger.root.info(
        'could not retrieve spotify home data due to ${receivedData['error']}, using cached data if possible',
      );
    }

    List? spotifyPlaylists = [];
    await callSpotifyFunction(
      function: (String accessToken) async =>
          {spotifyPlaylists = await SpotifyApi().getUserPlaylists(accessToken)},
    );

    if (spotifyPlaylists != null) {
      if (spotifyPlaylists!.isNotEmpty) {
        for (final element in spotifyPlaylists!) {
          if (!playlistNames.contains(element['title'])) {
            playlistNames.add(element['title']);
            playlistDetails[element['title']] = {
              'count': (element['tracks'] as List).length,
              'imagesList': [element],
              'source': 'spotify',
            };
            await Hive.box('settings').put('playlistNames', playlistNames);
            await Hive.box('settings').put('playlistDetails', playlistDetails);
          } else {
            if (playlistDetails[element['title']]['imagesList'][0]
                    ['snapshot_id'] !=
                element['snapshot_id']) {
              playlistDetails.remove(element['title']);
              playlistDetails[element['title']] = {
                'count': (element['tracks'] as List).length,
                'imagesList': [element],
                'source': 'spotify',
              };
              await Hive.box('settings')
                  .put('playlistDetails', playlistDetails);
            }
          }
        }
      }
      bool deleting = false;
      for (final element in [...playlistNames]) {
        if (playlistDetails[element]?['source'] != null) {
          final exists = spotifyPlaylists!
              .map((element) => element['id'])
              .contains(playlistDetails[element]?['imagesList']?[0]?['id']);
          if (!exists) {
            deleting = true;
            playlistDetails.remove(element);
            playlistNames.remove(element);
          }
        }
      }
      if (deleting) {
        Hive.box('settings').put('playlistNames', playlistNames);
        Hive.box('settings').put('playlistDetails', playlistDetails);
      }
    }
    setState(() {});
  }

  String getSubTitle(Map item) {
    final type = item['type'];
    switch (type) {
      case 'charts':
        return '';
      case 'radio_station':
        return 'Radio • ${(item['subtitle']?.toString() ?? '').isEmpty ? 'JioSaavn' : item['subtitle']?.toString().unescape()}';
      case 'playlist':
        return (item['subtitle']?.toString() ?? '').isEmpty
            ? 'JioSaavn'
            : item['subtitle'].toString().unescape();
      case 'song':
        return 'Single • ${item['artist']?.toString().unescape()}';
      case 'mix':
        return 'Mix • ${(item['subtitle']?.toString() ?? '').isEmpty ? 'JioSaavn' : item['subtitle'].toString().unescape()}';
      case 'show':
        return 'Podcast • ${(item['subtitle']?.toString() ?? '').isEmpty ? 'JioSaavn' : item['subtitle'].toString().unescape()}';
      case 'album':
        final artists = item['more_info']?['artistMap']?['artists']
            .map((artist) => artist['name'])
            .toList();
        if (artists != null) {
          return 'Album • ${artists?.join(', ')?.toString().unescape()}';
        } else if (item['subtitle'] != null && item['subtitle'] != '') {
          return 'Album • ${item['subtitle']?.toString().unescape()}';
        }
        return 'Album';
      default:
        final artists = item['more_info']?['artistMap']?['artists']
            .map((artist) => artist['name'])
            .toList();
        return artists?.join(', ')?.toString().unescape() ?? '';
    }
  }

  int likedCount() {
    return Hive.box('Favorite Songs').length;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!fetched) {
      getHomePageData();
      fetched = true;
    }
    double boxSize =
        MediaQuery.of(context).size.height > MediaQuery.of(context).size.width
            ? MediaQuery.of(context).size.width / 2
            : MediaQuery.of(context).size.height / 2.5;
    if (boxSize > 250) boxSize = 250;
    if (playlistNames.length >= 3) {
      recentIndex = 0;
      playlistIndex = 1;
    } else {
      recentIndex = 1;
      playlistIndex = 0;
    }
    return (data.isEmpty && recentList.isEmpty)
        ? const Center(
            child: CircularProgressIndicator(),
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            itemCount: data.isEmpty ? 2 : lists.length,
            itemBuilder: (context, idx) {
              if (idx == recentIndex) {
                return (recentList.isEmpty ||
                        !(Hive.box('settings')
                            .get('showRecent', defaultValue: true) as bool))
                    ? const SizedBox()
                    : Column(
                        children: [
                          GestureDetector(
                            child: Row(
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(15, 10, 15, 5),
                                  child: Text(
                                    AppLocalizations.of(context)!.lastSession,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pushNamed(context, '/recent');
                            },
                          ),
                          HorizontalAlbumsListSeparated(
                            songsList: recentList,
                            onTap: (int idx) {
                              PlayerInvoke.init(
                                songsList: [recentList[idx]],
                                index: 0,
                                isOffline: false,
                              );
                            },
                          ),
                        ],
                      );
              }
              if (idx == playlistIndex) {
                return (playlistNames.isEmpty ||
                        !(Hive.box('settings')
                            .get('showPlaylist', defaultValue: true) as bool) ||
                        (playlistNames.length == 1 &&
                            playlistNames.first == 'Favorite Songs' &&
                            likedCount() == 0))
                    ? const SizedBox()
                    : Column(
                        children: [
                          GestureDetector(
                            child: Row(
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(15, 10, 15, 5),
                                  child: Text(
                                    AppLocalizations.of(context)!.yourPlaylists,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pushNamed(context, '/playlists');
                            },
                          ),
                          SizedBox(
                            height: boxSize + 15,
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              itemCount: playlistNames.length,
                              itemBuilder: (context, index) {
                                final String name =
                                    playlistNames[index].toString();
                                final String showName =
                                    playlistDetails.containsKey(name)
                                        ? playlistDetails[name]['name']
                                                ?.toString() ??
                                            name
                                        : name;
                                final String? subtitle = playlistDetails[
                                                name] ==
                                            null ||
                                        playlistDetails[name]['count'] ==
                                            null ||
                                        playlistDetails[name]['count'] == 0
                                    ? null
                                    : '${playlistDetails[name]['count']} ${AppLocalizations.of(context)!.songs}';
                                return GestureDetector(
                                  child: SizedBox(
                                    width: boxSize - 30,
                                    child: HoverBox(
                                      child: (playlistDetails[name] == null ||
                                              playlistDetails[name]
                                                      ['imagesList'] ==
                                                  null ||
                                              (playlistDetails[name]
                                                      ['imagesList'] as List)
                                                  .isEmpty)
                                          ? Card(
                                              elevation: 5,
                                              color: Colors.black,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  10.0,
                                                ),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: name == 'Favorite Songs'
                                                  ? const Image(
                                                      image: AssetImage(
                                                        'assets/cover.jpg',
                                                      ),
                                                    )
                                                  : const Image(
                                                      image: AssetImage(
                                                        'assets/album.png',
                                                      ),
                                                    ),
                                            )
                                          : Collage(
                                              borderRadius: 10.0,
                                              imageList: playlistDetails[name]
                                                  ['imagesList'] as List,
                                              showGrid: true,
                                              placeholderImage:
                                                  'assets/cover.jpg',
                                            ),
                                      builder: ({
                                        Widget? child,
                                        required BuildContext context,
                                        required bool isHover,
                                      }) =>
                                          Card(
                                        color:
                                            isHover ? null : Colors.transparent,
                                        elevation: 0,
                                        margin: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10.0,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Column(
                                          children: [
                                            SizedBox.square(
                                              dimension: isHover
                                                  ? boxSize - 25
                                                  : boxSize - 30,
                                              child: child,
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10.0,
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    showName,
                                                    textAlign: TextAlign.center,
                                                    softWrap: false,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (subtitle != null &&
                                                      subtitle.isNotEmpty)
                                                    Text(
                                                      subtitle,
                                                      textAlign:
                                                          TextAlign.center,
                                                      softWrap: false,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.white38,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  onTap: () async {
                                    if (playlistDetails[name]?['imagesList']?[0]
                                            ?['snapshot_id'] ==
                                        null) {
                                      await Hive.openBox(name);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => LikedSongs(
                                            playlistName: name,
                                            showName: playlistDetails
                                                    .containsKey(name)
                                                ? playlistDetails[name]['name']
                                                        ?.toString() ??
                                                    name
                                                : name,
                                          ),
                                        ),
                                      );
                                    } else {
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          opaque: false,
                                          pageBuilder: (_, __, ___) =>
                                              SongsListPage(
                                            listItem:
                                                Map<dynamic, dynamic>.from(
                                              playlistDetails[name]
                                                  ['imagesList'][0] as Map,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      );
              }
              if (lists[idx] == 'likedArtists') {
                final List likedArtistsList = likedArtists.values.toList();
                return likedArtists.isEmpty
                    ? const SizedBox()
                    : Column(
                        children: [
                          Row(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(15, 10, 15, 5),
                                child: Text(
                                  'Liked Artists',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          HorizontalAlbumsList(
                            songsList: likedArtistsList,
                            onTap: (int idx) {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  opaque: false,
                                  pageBuilder: (_, __, ___) => ArtistSearchPage(
                                    data: likedArtistsList[idx] as Map,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
              }
              return (data[lists[idx]] == null ||
                      blacklistedHomeSections.contains(
                        data['modules'][lists[idx]]?['title']
                            ?.toString()
                            .toLowerCase(),
                      ))
                  ? const SizedBox()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
                          child: Row(
                            children: [
                              Flexible(
                                fit: FlexFit.tight,
                                child: Text(
                                  data['modules'][lists[idx]]?['title']
                                          ?.toString()
                                          .unescape() ??
                                      '',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                width: 8,
                              ),
                              /*GestureDetector(
                                child: Icon(
                                  Icons.block_rounded,
                                  color: Theme.of(context).disabledColor,
                                  size: 18,
                                ),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15.0),
                                        ),
                                        title: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!
                                              .blacklistHomeSections,
                                        ),
                                        content: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!
                                              .blacklistHomeSectionsConfirm,
                                        ),
                                        actions: [
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Theme.of(context)
                                                  .iconTheme
                                                  .color,
                                            ),
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },
                                            child: Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .no,
                                            ),
                                          ),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            ),
                                            onPressed: () async {
                                              Navigator.pop(context);
                                              blacklistedHomeSections.add(
                                                data['modules'][lists[idx]]
                                                        ?['title']
                                                    ?.toString()
                                                    .toLowerCase(),
                                              );
                                              Hive.box('settings').put(
                                                'blacklistedHomeSections',
                                                blacklistedHomeSections,
                                              );
                                              setState(() {});
                                            },
                                            child: Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .yes,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                            .colorScheme
                                                            .secondary ==
                                                        Colors.white
                                                    ? Colors.black
                                                    : null,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 5,
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),*/
                            ],
                          ),
                        ),
                        SizedBox(
                          height: boxSize + 15,
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: data['modules'][lists[idx]]?['title']
                                        ?.toString() ==
                                    'Radio Stations'
                                ? (data[lists[idx]] as List).length +
                                    likedRadio.length
                                : (data[lists[idx]] as List).length,
                            itemBuilder: (context, index) {
                              Map item;
                              if (data['modules'][lists[idx]]?['title']
                                      ?.toString() ==
                                  'Radio Stations') {
                                index < likedRadio.length
                                    ? item = likedRadio[index] as Map
                                    : item = data[lists[idx]]
                                        [index - likedRadio.length] as Map;
                              } else {
                                item = data[lists[idx]][index] as Map;
                              }
                              final currentSongList = data[lists[idx]]
                                  .where((e) => e['type'] == 'song')
                                  .toList();
                              final subTitle = getSubTitle(item);
                              item['subTitle'] = subTitle;
                              if (item.isEmpty) return const SizedBox();
                              return GestureDetector(
                                onLongPress: () {
                                  Feedback.forLongPress(context);
                                  showDialog(
                                    context: context,
                                    builder: (context) {
                                      return InteractiveViewer(
                                        child: Stack(
                                          children: [
                                            GestureDetector(
                                              onTap: () =>
                                                  Navigator.pop(context),
                                            ),
                                            AlertDialog(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(15.0),
                                              ),
                                              backgroundColor:
                                                  Colors.transparent,
                                              contentPadding: EdgeInsets.zero,
                                              content: Card(
                                                elevation: 5,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    item['type'] ==
                                                            'radio_station'
                                                        ? 1000.0
                                                        : 15.0,
                                                  ),
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child: CachedNetworkImage(
                                                  fit: BoxFit.cover,
                                                  errorWidget:
                                                      (context, _, __) =>
                                                          const Image(
                                                    fit: BoxFit.cover,
                                                    image: AssetImage(
                                                      'assets/cover.jpg',
                                                    ),
                                                  ),
                                                  imageUrl: getImageUrl(
                                                    item['image'].toString(),
                                                  ),
                                                  placeholder: (context, url) =>
                                                      Image(
                                                    fit: BoxFit.cover,
                                                    image: (item['type'] ==
                                                                'playlist' ||
                                                            item['type'] ==
                                                                'album')
                                                        ? const AssetImage(
                                                            'assets/album.png',
                                                          )
                                                        : item['type'] ==
                                                                'artist'
                                                            ? const AssetImage(
                                                                'assets/artist.png',
                                                              )
                                                            : const AssetImage(
                                                                'assets/cover.jpg',
                                                              ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                onTap: () async {
                                  if (item['type'] == 'radio_station') {
                                    ShowSnackBar().showSnackBar(
                                      context,
                                      AppLocalizations.of(context)!
                                          .connectingRadio,
                                      duration: const Duration(seconds: 2),
                                    );
                                    SaavnAPI()
                                        .createRadio(
                                      names: item['more_info']
                                                      ['featured_station_type']
                                                  .toString() ==
                                              'artist'
                                          ? [
                                              item['more_info']['query']
                                                  .toString(),
                                            ]
                                          : [item['id'].toString()],
                                      language: item['more_info']['language']
                                              ?.toString() ??
                                          'english',
                                      stationType: item['more_info']
                                              ['featured_station_type']
                                          .toString(),
                                    )
                                        .then((value) {
                                      if (value != null) {
                                        SaavnAPI()
                                            .getRadioSongs(stationId: value)
                                            .then((value) {
                                          PlayerInvoke.init(
                                            songsList: value,
                                            index: 0,
                                            isOffline: false,
                                            shuffle: true,
                                          );
                                          Navigator.pushNamed(
                                            context,
                                            '/player',
                                          );
                                        });
                                      }
                                    });
                                  } else {
                                    if (item['type'] == 'song') {
                                      PlayerInvoke.init(
                                        songsList: currentSongList as List,
                                        index: currentSongList.indexWhere(
                                          (e) => e['id'] == item['id'],
                                        ),
                                        isOffline: false,
                                      );
                                    }
                                    item['type'] == 'song'
                                        ? Navigator.pushNamed(
                                            context,
                                            '/player',
                                          )
                                        : Navigator.push(
                                            context,
                                            PageRouteBuilder(
                                              opaque: false,
                                              pageBuilder: (_, __, ___) =>
                                                  SongsListPage(
                                                listItem: item,
                                              ),
                                            ),
                                          );
                                  }
                                },
                                child: SizedBox(
                                  width: boxSize - 30,
                                  child: HoverBox(
                                    child: Card(
                                      elevation: 5,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          item['type'] == 'radio_station'
                                              ? 1000.0
                                              : 10.0,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: CachedNetworkImage(
                                        fit: BoxFit.cover,
                                        errorWidget: (context, _, __) =>
                                            const Image(
                                          fit: BoxFit.cover,
                                          image: AssetImage(
                                            'assets/cover.jpg',
                                          ),
                                        ),
                                        imageUrl: getImageUrl(
                                          item['image'].toString(),
                                        ),
                                        placeholder: (context, url) => Image(
                                          fit: BoxFit.cover,
                                          image: (item['type'] == 'playlist' ||
                                                  item['type'] == 'album')
                                              ? const AssetImage(
                                                  'assets/album.png',
                                                )
                                              : item['type'] == 'artist'
                                                  ? const AssetImage(
                                                      'assets/artist.png',
                                                    )
                                                  : const AssetImage(
                                                      'assets/cover.jpg',
                                                    ),
                                        ),
                                      ),
                                    ),
                                    builder: ({
                                      Widget? child,
                                      required BuildContext context,
                                      required bool isHover,
                                    }) =>
                                        Card(
                                      color:
                                          isHover ? null : Colors.transparent,
                                      elevation: 0,
                                      margin: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          10.0,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        children: [
                                          Stack(
                                            children: [
                                              SizedBox.square(
                                                dimension: isHover
                                                    ? boxSize - 25
                                                    : boxSize - 30,
                                                child: child,
                                              ),
                                              if (isHover &&
                                                  (item['type'] == 'song' ||
                                                      item['type'] ==
                                                          'radio_station'))
                                                Positioned.fill(
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.all(
                                                      4.0,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black54,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        item['type'] ==
                                                                'radio_station'
                                                            ? 1000.0
                                                            : 10.0,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: DecoratedBox(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.black87,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            1000.0,
                                                          ),
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .play_arrow_rounded,
                                                          size: 50.0,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (item['type'] ==
                                                      'radio_station' &&
                                                  (Platform.isAndroid ||
                                                      Platform.isIOS ||
                                                      isHover))
                                                Align(
                                                  alignment: Alignment.topRight,
                                                  child: IconButton(
                                                    icon: likedRadio
                                                            .contains(item)
                                                        ? const Icon(
                                                            Icons
                                                                .favorite_rounded,
                                                            color: Colors.red,
                                                          )
                                                        : const Icon(
                                                            Icons
                                                                .favorite_border_rounded,
                                                          ),
                                                    tooltip: likedRadio
                                                            .contains(item)
                                                        ? AppLocalizations.of(
                                                            context,
                                                          )!
                                                            .unlike
                                                        : AppLocalizations.of(
                                                            context,
                                                          )!
                                                            .like,
                                                    onPressed: () {
                                                      likedRadio.contains(item)
                                                          ? likedRadio
                                                              .remove(item)
                                                          : likedRadio
                                                              .add(item);
                                                      Hive.box('settings').put(
                                                        'likedRadio',
                                                        likedRadio,
                                                      );
                                                      setState(() {});
                                                    },
                                                  ),
                                                ),
                                              if (item['type'] == 'song' ||
                                                  item['duration'] != null)
                                                Align(
                                                  alignment: Alignment.topRight,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (isHover)
                                                        LikeButton(
                                                          mediaItem: null,
                                                          data: item,
                                                        ),
                                                      SongTileTrailingMenu(
                                                        data: item,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10.0,
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  item['title']
                                                          ?.toString()
                                                          .unescape() ??
                                                      '',
                                                  textAlign: TextAlign.center,
                                                  softWrap: false,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                if (subTitle != '')
                                                  Text(
                                                    subTitle,
                                                    textAlign: TextAlign.center,
                                                    softWrap: false,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white38,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
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
