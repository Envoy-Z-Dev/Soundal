import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:soundal/APIs/api.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/CustomWidgets/copy_clipboard.dart';
import 'package:soundal/CustomWidgets/download_button.dart';
import 'package:soundal/CustomWidgets/empty_screen.dart';
import 'package:soundal/CustomWidgets/gradient_containers.dart';
import 'package:soundal/CustomWidgets/like_button.dart';
import 'package:soundal/CustomWidgets/miniplayer.dart';
import 'package:soundal/CustomWidgets/search_bar.dart' as my_search;
import 'package:soundal/CustomWidgets/snackbar.dart';
import 'package:soundal/CustomWidgets/song_tile_trailing_menu.dart';
import 'package:soundal/Helpers/format.dart';
import 'package:soundal/Helpers/logger.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/Screens/Common/song_list.dart';
import 'package:soundal/Screens/Search/albums.dart';
import 'package:soundal/Screens/Search/artists.dart';
import 'package:soundal/Services/player_service.dart';
import 'package:soundal/Services/youtube_services.dart';

class SearchPage extends StatefulWidget {
  final String query;
  final bool fromHome;
  final bool autofocus;
  const SearchPage({
    super.key,
    required this.query,
    this.fromHome = false,
    this.autofocus = false,
  });

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';
  bool status = false;
  Map searchedData = {};
  Map position = {};
  List sortedKeys = [];
  final ValueNotifier<List<String>> topSearch = ValueNotifier<List<String>>(
    [],
  );
  bool fetched = false;
  bool alertShown = false;
  bool albumFetched = false;
  bool? fromHome;
  List search = Hive.box('settings').get(
    'search',
    defaultValue: [],
  ) as List;
  bool showHistory =
      Hive.box('settings').get('showHistory', defaultValue: true) as bool;
  bool liveSearch =
      Hive.box('settings').get('liveSearch', defaultValue: true) as bool;

  final controller = TextEditingController();

  @override
  void initState() {
    controller.text = widget.query;
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> fetchResults() async {
    // this fetches top 5 songs results
    Map result = {};

    try {
      await callSpotifyFunction(
        function: (String accessToken) async => {
          result = await SpotifyApi().fetchSearchResults(
            accessToken,
            searchQuery: query == '' ? widget.query : query,
            count: 5,
          )
        },
      );

      result['songs'] = await FormatResponse.parallelSpotifyListToYoutubeList(
        result['tracks'] as List,
      );

      final List songResults = result['songs'] as List;
      if (songResults.isNotEmpty) searchedData['Songs'] = songResults;
      fetched = true;
      await callSpotifyFunction(
        function: (String accessToken) async => {
          searchedData['Albums'] = (await SpotifyApi().fetchSearchResults(
            accessToken,
            searchQuery: query == '' ? widget.query : query,
            searchType: 'album',
            count: 5,
          ))?['albums']
        },
      );

      for (final element in searchedData['Albums'] as List) {
        element['image'] = element['images'].first['url'];
        element['title'] = element['name'];
        element['artist'] =
            (element['artists'] as List).map((e) => e['name']).join(', ');
        element['subtitle'] = element['artist'];
        element['count'] = element['total_tracks'];
      }

      await callSpotifyFunction(
        function: (String accessToken) async => {
          searchedData['Playlists'] = (await SpotifyApi().fetchSearchResults(
            accessToken,
            searchQuery: query == '' ? widget.query : query,
            searchType: 'playlist',
            count: 5,
          ))?['playlists']
        },
      );

      for (final element in searchedData['Playlists'] as List) {
        element['image'] = element['images']?.first['url'] ?? '';
        element['title'] = element['name'];
        element['artist'] = element['description'];
        element['subtitle'] = element['artist'];
      }

      await callSpotifyFunction(
        function: (String accessToken) async => {
          searchedData['Artists'] = (await SpotifyApi().fetchSearchResults(
            accessToken,
            searchQuery: query == '' ? widget.query : query,
            searchType: 'artist',
            count: 5,
          ))?['artists']
        },
      );

      for (final element in searchedData['Artists'] as List) {
        if ((element['images'] as List).isNotEmpty) {
          element['image'] = element['images'].first['url'];
        } else {
          element['image'] = '';
        }
        element['title'] = element['name'];
        element['subtitle'] =
            NumberFormat.compact().format(element['followers']['total']);
      }

      position = {'Albums': 1, 'Songs': 2, 'Playlists': 3, 'Artists': 4};
      sortedKeys = position.keys.toList();
    } on Exception catch (e) {
      Logger.root.severe('Error while searching: $e');
    }

    albumFetched = true;
    setState(
      () {},
    );
  }

  Future<void> getTrendingSearch() async {
    topSearch.value = await SaavnAPI().getTopSearches();
  }

  Widget nothingFound(BuildContext context) {
    if (!alertShown) {
      ShowSnackBar().showSnackBar(
        context,
        AppLocalizations.of(context)!.useVpn,
        duration: const Duration(seconds: 5),
      );
      alertShown = true;
    }
    return emptyScreen(
      context,
      0,
      ':( ',
      100,
      AppLocalizations.of(context)!.sorry,
      60,
      AppLocalizations.of(context)!.resultsNotFound,
      20,
    );
  }

  @override
  Widget build(BuildContext context) {
    fromHome ??= widget.fromHome;
    if (!status) {
      status = true;
      fromHome! ? getTrendingSearch() : fetchResults();
    }
    return GradientContainer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                backgroundColor: Colors.transparent,
                body: my_search.SearchBar(
                  onQueryChanged: (changedQuery) {
                    return YouTubeServices()
                        .getSearchSuggestions(query: changedQuery);
                  },
                  isYt: true,
                  controller: controller,
                  liveSearch: liveSearch,
                  autofocus: widget.autofocus,
                  hintText: AppLocalizations.of(context)!.searchText,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  body: (fromHome!)
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10.0,
                          ),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              const SizedBox(
                                height: 100,
                              ),
                              Align(
                                alignment: Alignment.topLeft,
                                child: Wrap(
                                  children: List<Widget>.generate(
                                    search.length,
                                    (int index) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5.0,
                                        ),
                                        child: GestureDetector(
                                          child: Chip(
                                            label: Text(
                                              search[index].toString(),
                                            ),
                                            labelStyle: TextStyle(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge!
                                                  .color,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            onDeleted: () {
                                              setState(() {
                                                search.removeAt(index);
                                                Hive.box('settings').put(
                                                  'search',
                                                  search,
                                                );
                                              });
                                            },
                                          ),
                                          onTap: () {
                                            setState(
                                              () {
                                                fetched = false;
                                                query = search
                                                    .removeAt(index)
                                                    .toString()
                                                    .trim();
                                                search.insert(
                                                  0,
                                                  query,
                                                );
                                                Hive.box('settings').put(
                                                  'search',
                                                  search,
                                                );
                                                controller.text = query;
                                                controller.selection =
                                                    TextSelection.fromPosition(
                                                  TextPosition(
                                                    offset: query.length,
                                                  ),
                                                );
                                                status = false;
                                                fromHome = false;
                                                searchedData = {};
                                              },
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              ValueListenableBuilder(
                                valueListenable: topSearch,
                                builder: (
                                  BuildContext context,
                                  List<String> value,
                                  Widget? child,
                                ) {
                                  if (value.isEmpty) return const SizedBox();
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              AppLocalizations.of(context)!
                                                  .trendingSearch,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary,
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.topLeft,
                                        child: Wrap(
                                          children: List<Widget>.generate(
                                            value.length,
                                            (int index) {
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 5.0,
                                                ),
                                                child: ChoiceChip(
                                                  label: Text(value[index]),
                                                  selectedColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .secondary
                                                          .withOpacity(0.2),
                                                  labelStyle: TextStyle(
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge!
                                                        .color,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                  ),
                                                  selected: false,
                                                  onSelected: (bool selected) {
                                                    if (selected) {
                                                      setState(
                                                        () {
                                                          fetched = false;
                                                          query = value[index]
                                                              .trim();
                                                          controller.text =
                                                              query;
                                                          controller.selection =
                                                              TextSelection
                                                                  .fromPosition(
                                                            TextPosition(
                                                              offset:
                                                                  query.length,
                                                            ),
                                                          );
                                                          status = false;
                                                          fromHome = false;
                                                          searchedData = {};
                                                          search.insert(
                                                            0,
                                                            value[index],
                                                          );
                                                          if (search.length >
                                                              10) {
                                                            search = search
                                                                .sublist(0, 10);
                                                          }
                                                          Hive.box('settings')
                                                              .put(
                                                            'search',
                                                            search,
                                                          );
                                                        },
                                                      );
                                                    }
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        )
                      : !fetched
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : (searchedData.isEmpty)
                              ? nothingFound(context)
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.only(
                                    top: 100,
                                  ),
                                  physics: const BouncingScrollPhysics(),
                                  child: Column(
                                    children: sortedKeys.map(
                                      (e) {
                                        /*final String key =
                                            position[e].toString();*/
                                        final List? value =
                                            searchedData[e] as List?;

                                        if (value == null) {
                                          return const SizedBox();
                                        }
                                        return Column(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 25,
                                                top: 10,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    e.toString(),
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .secondary,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  if (e != 'Top Result')
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .fromLTRB(
                                                        25,
                                                        0,
                                                        25,
                                                        0,
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .end,
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () {
                                                              if (e == 'Albums' ||
                                                                  e ==
                                                                      'Playlists' ||
                                                                  e ==
                                                                      'Artists') {
                                                                Navigator.push(
                                                                  context,
                                                                  PageRouteBuilder(
                                                                    opaque:
                                                                        false,
                                                                    pageBuilder: (
                                                                      _,
                                                                      __,
                                                                      ___,
                                                                    ) =>
                                                                        AlbumSearchPage(
                                                                      query: query ==
                                                                              ''
                                                                          ? widget
                                                                              .query
                                                                          : query,
                                                                      type: e
                                                                          .toString(),
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                              if (e.toString() ==
                                                                  'Songs') {
                                                                Navigator.push(
                                                                  context,
                                                                  PageRouteBuilder(
                                                                    opaque:
                                                                        false,
                                                                    pageBuilder: (
                                                                      _,
                                                                      __,
                                                                      ___,
                                                                    ) =>
                                                                        SongsListPage(
                                                                      listItem: {
                                                                        'id': query ==
                                                                                ''
                                                                            ? widget.query
                                                                            : query,
                                                                        'title':
                                                                            e.toString(),
                                                                        'type':
                                                                            'songs',
                                                                      },
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            },
                                                            child: Row(
                                                              children: [
                                                                Text(
                                                                  AppLocalizations
                                                                          .of(
                                                                    context,
                                                                  )!
                                                                      .viewAll,
                                                                  style:
                                                                      TextStyle(
                                                                    color: Theme
                                                                            .of(
                                                                      context,
                                                                    )
                                                                        .textTheme
                                                                        .bodySmall!
                                                                        .color,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                  ),
                                                                ),
                                                                Icon(
                                                                  Icons
                                                                      .chevron_right_rounded,
                                                                  color: Theme
                                                                          .of(
                                                                    context,
                                                                  )
                                                                      .textTheme
                                                                      .bodySmall!
                                                                      .color,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            ListView.builder(
                                              itemCount: value.length,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              shrinkWrap: true,
                                              padding: const EdgeInsets.only(
                                                left: 5,
                                                right: 10,
                                              ),
                                              itemBuilder: (context, index) {
                                                final int count = value[index]
                                                        ['count'] as int? ??
                                                    0;
                                                String countText = value[index]
                                                        ['artist']
                                                    .toString();
                                                count > 1
                                                    ? countText =
                                                        '$count ${AppLocalizations.of(context)!.songs}'
                                                    : countText =
                                                        '$count ${AppLocalizations.of(context)!.song}';
                                                return ListTile(
                                                  contentPadding:
                                                      const EdgeInsets.only(
                                                    left: 15.0,
                                                  ),
                                                  title: Text(
                                                    '${value[index]["title"]}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  subtitle: Text(
                                                    e.toString() == 'Albums' ||
                                                            (e.toString() ==
                                                                    'Top Result' &&
                                                                value[0][
                                                                        'type'] ==
                                                                    'album')
                                                        ? '$countText\n${value[index]["subtitle"]}'
                                                        : '${value[index]["subtitle"]}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  isThreeLine: e.toString() ==
                                                          'Albums' ||
                                                      (e.toString() ==
                                                              'Top Result' &&
                                                          value[0]['type'] ==
                                                              'album'),
                                                  leading: Card(
                                                    margin: EdgeInsets.zero,
                                                    elevation: 8,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        e.toString() ==
                                                                    'Artists' ||
                                                                (e.toString() ==
                                                                        'Top Result' &&
                                                                    value[0][
                                                                            'type'] ==
                                                                        'artist')
                                                            ? 50.0
                                                            : 7.0,
                                                      ),
                                                    ),
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    child: CachedNetworkImage(
                                                      fit: BoxFit.cover,
                                                      errorWidget:
                                                          (context, _, __) =>
                                                              Image(
                                                        fit: BoxFit.cover,
                                                        image: AssetImage(
                                                          e.toString() ==
                                                                      'Artists' ||
                                                                  (e.toString() ==
                                                                          'Top Result' &&
                                                                      value[0][
                                                                              'type'] ==
                                                                          'artist')
                                                              ? 'assets/artist.png'
                                                              : e.toString() ==
                                                                      'Songs'
                                                                  ? 'assets/cover.jpg'
                                                                  : 'assets/album.png',
                                                        ),
                                                      ),
                                                      imageUrl:
                                                          '${value[index]["image"].replaceAll('http:', 'https:')}',
                                                      placeholder:
                                                          (context, url) =>
                                                              Image(
                                                        fit: BoxFit.cover,
                                                        image: AssetImage(
                                                          e.toString() ==
                                                                      'Artists' ||
                                                                  (e.toString() ==
                                                                          'Top Result' &&
                                                                      value[0][
                                                                              'type'] ==
                                                                          'artist')
                                                              ? 'assets/artist.png'
                                                              : e.toString() ==
                                                                      'Songs'
                                                                  ? 'assets/cover.jpg'
                                                                  : 'assets/album.png',
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  trailing: e.toString() !=
                                                          'Albums'
                                                      ? e.toString() == 'Songs'
                                                          ? Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                DownloadButton(
                                                                  data: value[
                                                                          index]
                                                                      as Map,
                                                                  icon:
                                                                      'download',
                                                                ),
                                                                LikeButton(
                                                                  mediaItem:
                                                                      null,
                                                                  data: value[
                                                                          index]
                                                                      as Map,
                                                                ),
                                                                SongTileTrailingMenu(
                                                                  data: value[
                                                                          index]
                                                                      as Map,
                                                                ),
                                                              ],
                                                            )
                                                          : null
                                                      : Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            AlbumDownloadButton(
                                                              albumName: value[
                                                                          index]
                                                                      ['title']
                                                                  .toString(),
                                                              albumId: value[
                                                                          index]
                                                                      ['id']
                                                                  .toString(),
                                                            ),
                                                          ],
                                                        ),
                                                  onLongPress: () {
                                                    copyToClipboard(
                                                      context: context,
                                                      text:
                                                          '${value[index]["title"]}',
                                                    );
                                                  },
                                                  onTap: () {
                                                    if (e.toString() ==
                                                        'Songs') {
                                                      PlayerInvoke.init(
                                                        songsList: [
                                                          value[index]
                                                        ],
                                                        index: 0,
                                                        isOffline: false,
                                                      );
                                                    }
                                                    e.toString() == 'Songs'
                                                        ? Navigator.pushNamed(
                                                            context,
                                                            '/player',
                                                          )
                                                        : Navigator.push(
                                                            context,
                                                            PageRouteBuilder(
                                                              opaque: false,
                                                              pageBuilder: (
                                                                _,
                                                                __,
                                                                ___,
                                                              ) =>
                                                                  e.toString() ==
                                                                              'Artists' ||
                                                                          (e.toString() == 'Top Result' &&
                                                                              value[0]['type'] == 'artist')
                                                                      ? ArtistSearchPage(
                                                                          data: value[index]
                                                                              as Map,
                                                                        )
                                                                      : SongsListPage(
                                                                          listItem:
                                                                              value[index] as Map,
                                                                        ),
                                                            ),
                                                          );
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    ).toList(),
                                  ),
                                ),
                  onSubmitted: (String submittedQuery) {
                    setState(
                      () {
                        fetched = false;
                        query = submittedQuery;
                        status = false;
                        fromHome = false;
                        searchedData = {};
                      },
                    );
                  },
                  onQueryCleared: () {
                    setState(() {
                      fromHome = true;
                    });
                  },
                ),
              ),
            ),
            MiniPlayer(),
          ],
        ),
      ),
    );
  }
}
