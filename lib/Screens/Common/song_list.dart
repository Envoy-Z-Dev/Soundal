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
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soundal/APIs/api.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/CustomWidgets/bouncy_playlist_header_scroll_view.dart';
import 'package:soundal/CustomWidgets/copy_clipboard.dart';
import 'package:soundal/CustomWidgets/download_button.dart';
import 'package:soundal/CustomWidgets/gradient_containers.dart';
import 'package:soundal/CustomWidgets/like_button.dart';
import 'package:soundal/CustomWidgets/miniplayer.dart';
import 'package:soundal/CustomWidgets/playlist_popupmenu.dart';
import 'package:soundal/CustomWidgets/snackbar.dart';
import 'package:soundal/CustomWidgets/song_tile_trailing_menu.dart';
import 'package:soundal/Helpers/extensions.dart';
import 'package:soundal/Helpers/format.dart';
import 'package:soundal/Helpers/image_resolution_modifier.dart';
import 'package:soundal/Helpers/logging.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/Services/player_service.dart';
import 'package:soundal/Services/yt_music.dart';

class SongsListPage extends StatefulWidget {
  final Map listItem;

  const SongsListPage({
    super.key,
    required this.listItem,
  });

  @override
  _SongsListPageState createState() => _SongsListPageState();
}

class _SongsListPageState extends State<SongsListPage> {
  int page = 1;
  YtMusicService ytMusic = YtMusicService();
  bool loading = false;
  List songList = [];
  bool fetched = false;
  final ScrollController _scrollController = ScrollController();

  List playlistCache = Hive.box('cache').get(
    'spotifyPlaylists',
    defaultValue: [],
  ) as List;

  @override
  void initState() {
    super.initState();
    _fetchSongs().then((value) {
      _scrollController.addListener(() async {
        if (_scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent &&
            widget.listItem['type'].toString() == 'songs' &&
            !loading) {
          page += 1;
          await _fetchSongs();
        }
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _scrollController.dispose();
  }

  Future<void> _fetchSongs() async {
    loading = true;
    try {
      await ytMusic.init();
      switch (widget.listItem['type'].toString()) {
        case 'songs':
          Map result = {};

          await callSpotifyFunction(
            function: (String accessToken) async => {
              result = await SpotifyApi().fetchSearchResults(
                accessToken,
                searchQuery: widget.listItem['id'].toString(),
                count: 25,
                page: page,
              )
            },
          );

          await callSpotifyFunction(
            function: (String accessToken) async => {
              result = await SpotifyApi().fetchSearchResults(
                accessToken,
                searchQuery: widget.listItem['id'].toString(),
                count: 25,
                page: page,
              )
            },
          );

          songList.addAll(
            await FormatResponse.parallelSpotifyListToYoutubeList(
              result['tracks'] as List,
            ),
          );
          songList.addAll(
            await FormatResponse.parallelSpotifyListToYoutubeList(
              result['tracks'] as List,
            ),
          );

          setState(() {
            fetched = true;
            loading = false;
          });
        case 'album':
          //Retrieve spotify album songs then convert them to youtube
          Map receivedData = {};
          await callSpotifyFunction(
            function: (String accessToken) async => {
              receivedData = await SpotifyApi().getAlbumDetails(
                accessToken,
                widget.listItem['id'].toString(),
              )
            },
          );
          await callSpotifyFunction(
            function: (String accessToken) async => {
              receivedData = await SpotifyApi().getAlbumDetails(
                accessToken,
                widget.listItem['id'].toString(),
              )
            },
          );
          final spotifyTracks = [];
          for (final element in receivedData['tracks']['items'] as List) {
            element['album'] = receivedData;
            (element['album'] as Map).remove('tracks');
            spotifyTracks.add(element);
          }

          songList = await FormatResponse.parallelSpotifyListToYoutubeList(
            spotifyTracks,
          );

          fetched = true;
          loading = false;
          setState(() {});
        case 'playlist':
          final List songs = [];
          var playlistCached = playlistCache.firstWhere(
            (element) => element['id'] == widget.listItem['id'],
            orElse: () => null,
          );

          if (playlistCached == null) {
            await callSpotifyFunction(
              function: (String accessToken) async => {
                playlistCached = await SpotifyApi().getPlaylist(
                  accessToken,
                  widget.listItem['id'].toString(),
                )
              },
            );
          }

          if ((playlistCached['tracks'] as List).firstOrNull?['is_local'] !=
              null) {
            Logger.root.info(
              'No cached songs for ${widget.listItem['id']}, update cache to add songs',
            );
            if (widget.listItem['tracks'].runtimeType != List) {
              await callSpotifyFunction(
                function: (String accessToken) async => {
                  widget.listItem['tracks'] =
                      await SpotifyApi().getAllTracksOfPlaylist(
                    accessToken,
                    widget.listItem['id'].toString(),
                  )
                },
              );
            }

            for (final element in widget.listItem['tracks'] as List) {
              songs.add(element['track']);
            }
            songList = await FormatResponse.parallelSpotifyListToYoutubeList(
              songs,
            );
            playlistCached['tracks'] = songList;
            Hive.box('cache').put('spotifyPlaylists', playlistCache);
          } else {
            songList = playlistCached['tracks'] as List;
          }

          fetched = true;
          loading = false;

          setState(() {});
        case 'mix':
          SaavnAPI()
              .getSongFromToken(
            widget.listItem['perma_url'].toString().split('/').last,
            'mix',
          )
              .then((value) {
            setState(() {
              songList = value['songs'] as List;
              fetched = true;
              loading = false;
            });

            if (value['error'] != null && value['error'].toString() != '') {
              ShowSnackBar().showSnackBar(
                context,
                'Error: ${value["error"]}',
                duration: const Duration(seconds: 3),
              );
            }
          });
        case 'show':
          SaavnAPI()
              .getSongFromToken(
            widget.listItem['perma_url'].toString().split('/').last,
            'show',
          )
              .then((value) {
            setState(() {
              songList = value['songs'] as List;
              fetched = true;
              loading = false;
            });

            if (value['error'] != null && value['error'].toString() != '') {
              ShowSnackBar().showSnackBar(
                context,
                'Error: ${value["error"]}',
                duration: const Duration(seconds: 3),
              );
            }
          });
        default:
          setState(() {
            fetched = true;
            loading = false;
          });
          ShowSnackBar().showSnackBar(
            context,
            'Error: Unsupported Type ${widget.listItem['type']}',
            duration: const Duration(seconds: 3),
          );
          break;
      }
    } catch (e) {
      setState(() {
        fetched = true;
        loading = false;
      });
      Logger.root.severe(
        'Error in song_list with type ${widget.listItem["type"]}: $e',
      );
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
              body: !fetched
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : BouncyPlaylistHeaderScrollView(
                      scrollController: _scrollController,
                      actions: [
                        if (songList.isNotEmpty)
                          MultiDownloadButton(
                            data: songList,
                            playlistName:
                                widget.listItem['title']?.toString() ?? 'Songs',
                          ),
                        IconButton(
                          icon: const Icon(Icons.share_rounded),
                          tooltip: AppLocalizations.of(context)!.share,
                          onPressed: () {
                            Share.share(
                              widget.listItem['perma_url'].toString(),
                            );
                          },
                        ),
                        PlaylistPopupMenu(
                          data: songList,
                          showSave: widget.listItem['snapshot_id'] == null,
                          title:
                              widget.listItem['title']?.toString() ?? 'Songs',
                        ),
                      ],
                      title: widget.listItem['title']?.toString().unescape() ??
                          'Songs',
                      subtitle: '${songList.length} Songs',
                      secondarySubtitle:
                          widget.listItem['subTitle']?.toString() ??
                              widget.listItem['subtitle']?.toString(),
                      onPlayTap: () async {
                        PlayerInvoke.init(
                          songsList: songList,
                          //songsList: ytSongList,
                          index: 0,
                          isOffline: false,
                        );

                        Navigator.pushNamed(
                          context,
                          '/player',
                        );
                      },
                      onShuffleTap: () => PlayerInvoke.init(
                        songsList: songList,
                        index: 0,
                        isOffline: false,
                        shuffle: true,
                      ),
                      placeholderImage: 'assets/album.png',
                      imageUrl:
                          getImageUrl(widget.listItem['image']?.toString()),
                      sliverList: SliverList(
                        delegate: SliverChildListDelegate([
                          if (songList.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 20.0,
                                top: 5.0,
                                bottom: 5.0,
                              ),
                              child: Text(
                                AppLocalizations.of(context)!.songs,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ),
                          ...songList.map((entry) {
                            return ListTile(
                              contentPadding: const EdgeInsets.only(left: 15.0),
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
                              subtitle: Text(
                                '${entry["subtitle"]}',
                                overflow: TextOverflow.ellipsis,
                              ),
                              leading: Card(
                                margin: EdgeInsets.zero,
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(7.0),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CachedNetworkImage(
                                  fit: BoxFit.cover,
                                  errorWidget: (context, _, __) => const Image(
                                    fit: BoxFit.cover,
                                    image: AssetImage(
                                      'assets/cover.jpg',
                                    ),
                                  ),
                                  imageUrl:
                                      '${entry["image"].replaceAll('http:', 'https:')}',
                                  placeholder: (context, url) => const Image(
                                    fit: BoxFit.cover,
                                    image: AssetImage(
                                      'assets/cover.jpg',
                                    ),
                                  ),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DownloadButton(
                                    data: entry as Map,
                                    icon: 'download',
                                  ),
                                  LikeButton(
                                    mediaItem: null,
                                    data: entry,
                                  ),
                                  SongTileTrailingMenu(data: entry),
                                ],
                              ),
                              onTap: () {
                                PlayerInvoke.init(
                                  songsList: songList,
                                  index: songList.indexWhere(
                                    (element) => element == entry,
                                  ),
                                  isOffline: false,
                                );
                              },
                            );
                          })
                        ]),
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
