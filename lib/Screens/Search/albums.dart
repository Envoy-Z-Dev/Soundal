/*
 *  This file is part of Soundal (https://github.com/Sangwan5688/Soundal).
 * 
 * Soundal is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Soundal is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with Soundal.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Copyright (c) 2021-2022, Ankit Sangwan
 */

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/CustomWidgets/bouncy_sliver_scroll_view.dart';
import 'package:soundal/CustomWidgets/copy_clipboard.dart';
import 'package:soundal/CustomWidgets/download_button.dart';
import 'package:soundal/CustomWidgets/empty_screen.dart';
import 'package:soundal/CustomWidgets/gradient_containers.dart';
import 'package:soundal/CustomWidgets/miniplayer.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/Screens/Common/song_list.dart';
import 'package:soundal/Screens/Search/artists.dart';

class AlbumSearchPage extends StatefulWidget {
  final String query;
  final String type;

  const AlbumSearchPage({
    super.key,
    required this.query,
    required this.type,
  });

  @override
  _AlbumSearchPageState createState() => _AlbumSearchPageState();
}

class _AlbumSearchPageState extends State<AlbumSearchPage> {
  int page = 1;
  bool loading = false;
  List<Map<dynamic, dynamic>>? _searchedList;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent &&
          !loading) {
        page += 1;
        _fetchData();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _scrollController.dispose();
  }

  void _fetchData() {
    loading = true;
    final List<Map<dynamic, dynamic>> temp = _searchedList ?? [];
    switch (widget.type) {
      case 'Playlists':
        callSpotifyFunction(
          function: (String accessToken) async => {
            await SpotifyApi()
                .fetchSearchResults(
                  accessToken,
                  searchQuery: widget.query,
                  searchType: 'playlist',
                  count: 50,
                )
                .then(
                  (value) => {
                    temp.addAll(List<Map>.from(value['playlists'] as List)),
                    for (final element in temp)
                      {
                        element['image'] =
                            element['images']?.first['url'] ?? '',
                        element['title'] = element['name'],
                        element['artist'] = element['description'],
                        element['subtitle'] = element['artist'],
                      },
                    setState(() {
                      _searchedList = temp;
                      loading = false;
                    }),
                  },
                )
          },
        );
        break;
      case 'Albums':
        callSpotifyFunction(
          function: (String accessToken) async => {
            await SpotifyApi()
                .fetchSearchResults(
                  accessToken,
                  searchQuery: widget.query,
                  searchType: 'album',
                  count: 50,
                )
                .then(
                  (value) => {
                    temp.addAll(List<Map>.from(value['albums'] as List)),
                    for (final element in temp)
                      {
                        element['image'] = element['images'].first['url'],
                        element['title'] = element['name'],
                        element['artist'] = (element['artists'] as List)
                            .map((e) => e['name'])
                            .join(', '),
                        element['subtitle'] = element['artist'],
                        element['count'] = element['total_tracks'],
                      },
                    setState(() {
                      _searchedList = temp;
                      loading = false;
                    }),
                  },
                )
          },
        );
        break;
      case 'Artists':
        callSpotifyFunction(
          function: (String accessToken) async => {
            await SpotifyApi()
                .fetchSearchResults(
                  accessToken,
                  searchQuery: widget.query,
                  searchType: 'artist',
                  count: 50,
                )
                .then(
                  (value) => {
                    temp.addAll(List<Map>.from(value['artists'] as List)),
                    for (final element in temp)
                      {
                        element['title'] = element['name'],
                        if ((element['images'] as List).isNotEmpty)
                          {
                            element['image'] = element['images'].first['url'],
                          }
                        else
                          {
                            element['image'] = '',
                          },
                        element['title'] = element['name'],
                        element['subtitle'] = NumberFormat.compact()
                            .format(element['followers']['total']),
                      },
                    setState(() {
                      _searchedList = temp;
                      loading = false;
                    }),
                  },
                )
          },
        );
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientContainer(
      child: Column(
        children: [
          Expanded(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: _searchedList == null
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _searchedList!.isEmpty
                      ? emptyScreen(
                          context,
                          0,
                          ':( ',
                          100,
                          AppLocalizations.of(context)!.sorry,
                          60,
                          AppLocalizations.of(context)!.resultsNotFound,
                          20,
                        )
                      : BouncyImageSliverScrollView(
                          scrollController: _scrollController,
                          title: widget.type,
                          placeholderImage: widget.type == 'Artists'
                              ? 'assets/artist.png'
                              : 'assets/album.png',
                          sliverList: SliverList(
                            delegate: SliverChildListDelegate(
                              _searchedList!.map(
                                (Map entry) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: ListTile(
                                      title: Text(
                                        '${entry["title"]}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      onLongPress: () {
                                        copyToClipboard(
                                          context: context,
                                          text: '${entry["title"]}',
                                        );
                                      },
                                      subtitle: entry['subtitle'] == ''
                                          ? null
                                          : Text(
                                              '${entry["subtitle"]}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                      leading: Card(
                                        margin: EdgeInsets.zero,
                                        elevation: 8,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            widget.type == 'Artists'
                                                ? 50.0
                                                : 7.0,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: CachedNetworkImage(
                                          fit: BoxFit.cover,
                                          errorWidget: (context, _, __) =>
                                              Image(
                                            fit: BoxFit.cover,
                                            image: AssetImage(
                                              widget.type == 'Artists'
                                                  ? 'assets/artist.png'
                                                  : 'assets/album.png',
                                            ),
                                          ),
                                          imageUrl:
                                              '${entry["image"].replaceAll('http:', 'https:')}',
                                          placeholder: (context, url) => Image(
                                            fit: BoxFit.cover,
                                            image: AssetImage(
                                              widget.type == 'Artists'
                                                  ? 'assets/artist.png'
                                                  : 'assets/album.png',
                                            ),
                                          ),
                                        ),
                                      ),
                                      trailing: widget.type != 'Albums'
                                          ? null
                                          : AlbumDownloadButton(
                                              albumName:
                                                  entry['title'].toString(),
                                              albumId: entry['id'].toString(),
                                            ),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          PageRouteBuilder(
                                            opaque: false,
                                            pageBuilder: (_, __, ___) =>
                                                widget.type == 'Artists'
                                                    ? ArtistSearchPage(
                                                        data: entry,
                                                      )
                                                    : SongsListPage(
                                                        listItem: entry,
                                                      ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ).toList(),
                            ),
                          ),
                        ),
            ),
          ),
          MiniPlayer(),
        ],
      ),
    );
  }
}
