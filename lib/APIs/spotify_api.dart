import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:soundal/Helpers/logging.dart';

class SpotifyApi {
  final List<String> _scopes = [
    'user-read-private',
    'user-read-email',
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-library-read',
  ];

  /// You can signup for spotify developer account and get your own clientID and clientSecret in case you don't want to use these
  final String clientID = 'c72a8d6f500e494994308f5c49ba4745';
  final String redirectUrl = 'app://soundal/auth';
  final String spotifyApiUrl = 'https://accounts.spotify.com/api';
  final String spotifyApiBaseUrl = 'https://api.spotify.com/v1';
  final String spotifyUserPlaylistEndpoint = '/me/playlists';
  final String spotifyPlaylistTrackEndpoint = '/playlists';
  final String spotifyRegionalChartsEndpoint = '/views/charts-regional';
  final String spotifyFeaturedPlaylistsEndpoint = '/browse/featured-playlists';
  final String spotifyUserEndpoint = '/me';
  final String spotifyAlbumEndpoint = '/albums';
  final String spotifyArtistEndpoint = '/artists';
  final String spotifySearchEndpoint = '/search';
  final String spotifyBaseUrl = 'https://accounts.spotify.com';
  final String requestToken = 'https://accounts.spotify.com/api/token';
  late final String codeVerifier;
  late final String codeChallenge;

  String requestAuthorization() {
    codeVerifier = generateRandomString(127);
    codeChallenge = createCodeChallenge(codeVerifier);
    return 'https://accounts.spotify.com/authorize?client_id=$clientID&response_type=code&code_challenge_method=S256&code_challenge=$codeChallenge&redirect_uri=$redirectUrl&scope=${_scopes.join('%20')}';
  }

  String generateRandomString(int len) {
    final Random r = Random();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(len, (index) => chars[r.nextInt(chars.length)]).join();
  }

  String createCodeChallenge(String codeVerifier) {
    return base64Url
        .encode(sha256.convert(ascii.encode(codeVerifier)).bytes)
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
  }

  Future<List<String>> getAccessToken({
    String? code,
    String? refreshToken,
  }) async {
    Map<String, String>? body;
    Map<String, String>? headers;
    if (code != null) {
      body = {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUrl,
        'client_id': clientID,
        'code_verifier': codeVerifier,
      };
    } else if (refreshToken != null) {
      body = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientID,
      };
      headers = {'Content-Type': 'application/x-www-form-urlencoded'};
    }

    if (body == null) {
      return [];
    }

    try {
      final Uri path = Uri.parse(requestToken);
      final response = await post(path, body: body, headers: headers);

      if (response.statusCode == 200) {
        final Map result = jsonDecode(response.body) as Map;
        return <String>[
          result['access_token'].toString(),
          result['refresh_token'].toString(),
          result['expires_in'].toString(),
        ];
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify access token: $e');
    }
    return [];
  }

  Future<List?> getUserPlaylists(String accessToken) async {
    try {
      final Uri path =
          Uri.parse('$spotifyApiBaseUrl$spotifyUserPlaylistEndpoint?limit=50');

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      final List<Map> songsData = [];
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final playlistCache = Hive.box('cache').get(
          'spotifyPlaylists',
          defaultValue: [],
        ) as List;
        for (final element in result['items'] as List) {
          final cachedPlaylist = playlistCache.isNotEmpty
              ? playlistCache.where((x) => x['id'] == element['id']).firstOrNull
              : null;

          Map playlistObject = {
            'title': element['name'],
            'id': element['id'],
            'snapshot_id': element['snapshot_id'],
            'subtitle': element['description'],
            'image': element['images'][0]['url'],
            'perma_url': element['external_urls']['spotify'],
            'type': element['type'],
            'uri': element['uri'],
          };

          if (cachedPlaylist != null) {
            Logger.root.info('Found cached playlist for ${element["id"]}');
            playlistObject = Map.from(cachedPlaylist as Map);
            if (cachedPlaylist['snapshot_id'] != element['snapshot_id'] ||
                (cachedPlaylist['tracks'] as List).length !=
                    element['tracks']['total']) {
              Logger.root.info(
                'Cached playlist for ${element["id"]} has changed, update cache',
              );
              playlistCache.remove(cachedPlaylist);
              playlistObject['tracks'] =
                  await SpotifyApi().getAllTracksOfPlaylist(
                accessToken,
                element['id'].toString(),
              );
              playlistCache.add(playlistObject);
              Hive.box('cache').put('spotifyPlaylists', playlistCache);
            }
          } else {
            Logger.root.info('New playlist ${element["id"]}, add to cache');
            playlistObject['tracks'] =
                await SpotifyApi().getAllTracksOfPlaylist(
              accessToken,
              element['id'].toString(),
            );
            playlistCache.add(playlistObject);
            Hive.box('cache').put('spotifyPlaylists', playlistCache);
          }
          songsData.add(playlistObject);
        }
      } else {
        throw Exception('Spotify error: ${jsonDecode(response.body)}');
      }
      return songsData;
    } catch (e) {
      Logger.root.severe('Error in getting spotify user playlists: $e');
      return null;
    }
  }

  Future<dynamic> getPlaylist(String accessToken, String playlistId) async {
    try {
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl$spotifyPlaylistTrackEndpoint/$playlistId',
      );

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      Map songsData = {};
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final playlistCache = Hive.box('cache').get(
          'spotifyPlaylists',
          defaultValue: [],
        ) as List;
        final element = result;
        final cachedPlaylist = playlistCache.isNotEmpty
            ? playlistCache.where((x) => x['id'] == element['id']).firstOrNull
            : null;

        Map playlistObject = {
          'title': element['name'],
          'id': element['id'],
          'snapshot_id': element['snapshot_id'],
          'subtitle': element['description'],
          'image': element['images'][0]['url'],
          'perma_url': element['external_urls']['spotify'],
          'type': element['type'],
          'uri': element['uri'],
        };

        if (cachedPlaylist != null) {
          Logger.root.info('Found cached playlist for ${element["id"]}');
          playlistObject = Map.from(cachedPlaylist as Map);
          if (cachedPlaylist['snapshot_id'] != element['snapshot_id'] ||
              (cachedPlaylist['tracks'] as List).length !=
                  element['tracks']['total']) {
            Logger.root.info(
              'Cached playlist for ${element["id"]} has changed, update cache',
            );
            playlistCache.remove(cachedPlaylist);
            playlistObject['tracks'] =
                await SpotifyApi().getAllTracksOfPlaylist(
              accessToken,
              element['id'].toString(),
            );
            playlistCache.add(playlistObject);
            Hive.box('cache').put('spotifyPlaylists', playlistCache);
          }
        } else {
          Logger.root.info('New playlist ${element["id"]}, add to cache');
          playlistObject['tracks'] = await SpotifyApi().getAllTracksOfPlaylist(
            accessToken,
            element['id'].toString(),
          );
          playlistCache.add(playlistObject);
          Hive.box('cache').put('spotifyPlaylists', playlistCache);
        }
        songsData = playlistObject;
      } else {
        throw Exception('Spotify error: ${jsonDecode(response.body)}');
      }
      return songsData;
    } catch (e) {
      Logger.root.severe('Error in getting spotify playlist $playlistId: $e');
      return null;
    }
  }

  Future<List> getAllTracksOfPlaylist(
    String accessToken,
    String playlistId,
  ) async {
    final List tracks = [];
    int totalTracks = 100;

    final Map data = await SpotifyApi().getHundredTracksOfPlaylist(
      accessToken,
      playlistId,
      0,
    );
    totalTracks = data['total'] as int;
    tracks.addAll(data['tracks'] as List);

    if (totalTracks > 100) {
      for (int i = 1; i * 100 <= totalTracks; i++) {
        final Map data = await SpotifyApi().getHundredTracksOfPlaylist(
          accessToken,
          playlistId,
          i * 100,
        );
        tracks.addAll(data['tracks'] as List);
      }
    }
    return tracks;
  }

  Future<Map> getHundredTracksOfPlaylist(
    String accessToken,
    String playlistId,
    int offset,
  ) async {
    try {
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl$spotifyPlaylistTrackEndpoint/$playlistId/tracks?limit=100&offset=$offset',
      );
      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final result = await jsonDecode(response.body);
        final List tracks = result['items'] as List;
        final int total = result['total'] as int;
        return {'tracks': tracks, 'total': total};
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify playlist tracks: $e');
    }
    return {};
  }

  Future<Map> getTrackDetails(String accessToken, String trackId) async {
    final Uri path = Uri.parse(
      '$spotifyApiBaseUrl/tracks/$trackId',
    );
    final response = await get(
      path,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body) as Map;
      return result;
    }
    return {};
  }

  Future<List<Map>> getFeaturedPlaylists(
    String accessToken,
    String country,
  ) async {
    try {
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl/browse/featured-playlists?country=$country&offset=0&limit=20',
      );
      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );

      final playlistCache = Hive.box('cache').get(
        'spotifyPlaylists',
        defaultValue: [],
      ) as List;
      final List<Map> songsData = [];
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        for (final element in result['playlists']['items'] as List) {
          final cachedPlaylist = playlistCache.isNotEmpty
              ? playlistCache.where((x) => x['id'] == element['id']).firstOrNull
              : null;

          Map playlistObject = {
            'title': element['name'],
            'id': element['id'],
            'snapshot_id': element['snapshot_id'],
            'subtitle': element['description'],
            'image': element['images'][0]['url'],
            'perma_url': element['external_urls']['spotify'],
            'type': element['type'],
            'uri': element['uri'],
            'section': result['message'],
          };

          if (cachedPlaylist != null) {
            Logger.root.info('Found cached playlist for ${element["id"]}');
            playlistObject = Map.from(cachedPlaylist as Map);
            if (cachedPlaylist['snapshot_id'] != element['snapshot_id'] ||
                (cachedPlaylist['tracks'] as List).length !=
                    element['tracks']['total']) {
              Logger.root.info(
                'Cached playlist for ${element["id"]} has changed, update cache',
              );
              playlistCache.remove(cachedPlaylist);
              playlistObject['tracks'] =
                  await SpotifyApi().getAllTracksOfPlaylist(
                accessToken,
                element['id'].toString(),
              );
              playlistCache.add(playlistObject);
              Hive.box('cache').put('spotifyPlaylists', playlistCache);
            }
          } else {
            Logger.root.info('New playlist ${element["id"]}, add to cache');
            playlistObject['tracks'] =
                await SpotifyApi().getAllTracksOfPlaylist(
              accessToken,
              element['id'].toString(),
            );
            playlistCache.add(playlistObject);
            Hive.box('cache').put('spotifyPlaylists', playlistCache);
          }
          songsData.add(playlistObject);
        }
      } else {
        throw Exception('Spotify error: ${jsonDecode(response.body)}');
      }
      return songsData;
    } catch (e) {
      Logger.root.severe('Error in getting spotify featured playlists: $e');
      return List.empty();
    }
  }

  Future<Map> getUserDetails(String accessToken) async {
    try {
      final Uri path = Uri.parse('$spotifyApiBaseUrl$spotifyUserEndpoint');

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map;
        return result;
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify user details: $e');
    }
    return {};
  }

  Future<Map> fetchHomePageData(String accessToken, String country) async {
    final Map result = {};
    result['collections'] = [];
    result['modules'] = {};
    try {
      final List receivedData =
          await getFeaturedPlaylists(accessToken, country);
      if (receivedData.isNotEmpty) {
        result['spotify_featured'] = receivedData;
      }

      (result['collections'] as List).addAll(result.keys.skip(2));
      int i = 1;
      for (final item in result['collections'] as List) {
        result['modules']
            [item] = {'title': result[item][0]['section'], 'position': i};
        i++;
      }
    } on Exception catch (e) {
      result['error'] = e;
    }
    return result;
  }

  Future<Map> getAlbumDetails(String accessToken, String albumId) async {
    try {
      final Uri path =
          Uri.parse('$spotifyApiBaseUrl$spotifyAlbumEndpoint/$albumId');

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map;
        return result;
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify album: $e');
    }
    return {};
  }

  Future<Map> getArtistDetails(
    String accessToken,
    String artistId, {
    String category = '',
    String sortOrder = '',
  }) async {
    final Map result = {'artist': {}};
    final Map<String, List> data = {};
    try {
      final Uri path =
          Uri.parse('$spotifyApiBaseUrl$spotifyArtistEndpoint/$artistId');

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final artistResult = jsonDecode(response.body) as Map;
        result['artist']['perma_url'] =
            artistResult['external_urls']['spotify'];
        result['artist']['image'] = artistResult['images'].first['url'];
        result['sections'] = data;
        final user = await getUserDetails(accessToken);
        result['sections']['Top Songs'] = await getArtistTopTracks(
          accessToken,
          user['country']?.toString() ?? 'GB',
          artistId,
          category: category,
          sortOrder: sortOrder,
        );
        result['sections']['Singles'] = await getArtistAlbums(
          accessToken,
          artistId,
          category: category,
          sortOrder: sortOrder,
        );
        result['sections']['Related Artists'] = await getArtistRelatedArtists(
          accessToken,
          artistId,
          category: category,
          sortOrder: sortOrder,
        );
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify artist details: $e');
    }
    return result;
  }

  Future<List> getArtistTopTracks(
    String accessToken,
    String market,
    String artistId, {
    String category = '',
    String sortOrder = '',
  }) async {
    List result = [];
    try {
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl$spotifyArtistEndpoint/$artistId/top-tracks?market=$market',
      );

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        result = (jsonDecode(response.body) as Map)['tracks'] as List;
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify artist top songs: $e');
    }
    return result;
  }

  Future<List> getArtistAlbums(
    String accessToken,
    String artistId, {
    String category = '',
    String sortOrder = '',
  }) async {
    List result = [];
    try {
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl$spotifyArtistEndpoint/$artistId/albums?include_groups=single,album,appears_on,compilation&limit=50&offset=0',
      );

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        result = (jsonDecode(response.body) as Map)['items'] as List;
        result.sort((b, a) {
          return a['release_date']
              .toString()
              .compareTo(b['release_date'].toString());
        });
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify artist albums: $e');
    }
    return result;
  }

  Future<List> getArtistRelatedArtists(
    String accessToken,
    String artistId, {
    String category = '',
    String sortOrder = '',
  }) async {
    List result = [];
    try {
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl$spotifyArtistEndpoint/$artistId/related-artists',
      );

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        result = (jsonDecode(response.body) as Map)['artists'] as List;
      }
    } catch (e) {
      Logger.root.severe('Error in getting spotify artist related artists: $e');
    }
    return result;
  }

  Future<Map> fetchSearchResults(
    String accessToken, {
    required String searchQuery,
    String searchType = 'track',
    int count = 20,
    int page = 1,
  }) async {
    try {
      final res = {};
      final Uri path = Uri.parse(
        '$spotifyApiBaseUrl$spotifySearchEndpoint?q=$searchQuery&type=$searchType&limit=$count&offset=${(page - 1) * count}',
      );

      final response = await get(
        path,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map;

        switch (searchType) {
          case 'track':
            res['tracks'] = result['tracks']['items'];
          case 'album':
            res['albums'] = result['albums']['items'];
          case 'playlist':
            res['playlists'] = result['playlists']['items'];
          case 'artist':
            res['artists'] = result['artists']['items'];
        }
      }
      return res;
    } catch (e) {
      Logger.root.severe('Error in fetchSongSearchResults: $e');
      return {
        'tracks': List.empty(),
        'error': e,
      };
    }
  }
}
