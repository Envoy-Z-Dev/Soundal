import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:rxdart/rxdart.dart';
import 'package:soundal/APIs/api.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/Helpers/just_audio.dart';
//import 'package:just_audio/just_audio.dart';
import 'package:soundal/Helpers/logging.dart';
import 'package:soundal/Helpers/mediaitem_converter.dart';
import 'package:soundal/Helpers/playlist.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/Screens/Player/audioplayer.dart';
import 'package:soundal/Services/isolate_service.dart';
import 'package:soundal/Services/yt_music.dart';
import 'package:soundal/main.dart';

class AudioPlayerHandlerImpl extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements AudioPlayerHandler {
  int? count;
  Timer? _sleepTimer;
  RestartableTimer? _idleTimer;
  bool recommend = true;
  bool loadStart = true;
  bool useDown = true;
  AndroidEqualizerParameters? _equalizerParams;

  late AudioPlayer? _player;
  late String preferredQuality;
  late List<int> preferredCompactNotificationButtons = [1, 2, 3];
  late bool resetOnSkip;
  // late String? stationId = '';
  // late List<String> stationNames = [];
  // late String stationType = 'entity';
  late bool cacheSong;
  final _equalizer = AndroidEqualizer();

  Box downloadsBox = Hive.box('downloads');
  final List<String> refreshLinks = [];
  bool jobRunning = false;

  final BehaviorSubject<List<MediaItem>> _recentSubject =
      BehaviorSubject.seeded(<MediaItem>[]);
  final _playlist = ConcatenatingAudioSource(children: []);
  @override
  final BehaviorSubject<double> volume = BehaviorSubject.seeded(1.0);
  @override
  final BehaviorSubject<double> speed = BehaviorSubject.seeded(1.0);
  final _mediaItemExpando = Expando<MediaItem>();

  Stream<List<IndexedAudioSource>> get _effectiveSequence => Rx.combineLatest3<
              List<IndexedAudioSource>?,
              List<int>?,
              bool,
              List<IndexedAudioSource>?>(_player!.sequenceStream,
          _player!.shuffleIndicesStream, _player!.shuffleModeEnabledStream,
          (sequence, shuffleIndices, shuffleModeEnabled) {
        if (sequence == null) return [];
        if (!shuffleModeEnabled) return sequence;
        if (shuffleIndices == null) return null;
        if (shuffleIndices.length != sequence.length) return null;
        return shuffleIndices.map((i) => sequence[i]).toList();
      }).whereType<List<IndexedAudioSource>>();

  int? getQueueIndex(
    int? currentIndex,
    List<int>? shuffleIndices, {
    bool shuffleModeEnabled = false,
  }) {
    final effectiveIndices = _player!.effectiveIndices ?? [];
    final shuffleIndicesInv = List.filled(effectiveIndices.length, 0);
    for (var i = 0; i < effectiveIndices.length; i++) {
      shuffleIndicesInv[effectiveIndices[i]] = i;
    }
    return (shuffleModeEnabled &&
            ((currentIndex ?? 0) < shuffleIndicesInv.length))
        ? shuffleIndicesInv[currentIndex ?? 0]
        : currentIndex;
  }

  @override
  Stream<QueueState> get queueState =>
      Rx.combineLatest3<List<MediaItem>, PlaybackState, List<int>, QueueState>(
        queue,
        playbackState,
        _player!.shuffleIndicesStream.whereType<List<int>>(),
        (queue, playbackState, shuffleIndices) => QueueState(
          queue,
          playbackState.queueIndex,
          playbackState.shuffleMode == AudioServiceShuffleMode.all
              ? shuffleIndices
              : null,
          playbackState.repeatMode,
        ),
      ).where(
        (state) =>
            state.shuffleIndices == null ||
            state.queue.length == state.shuffleIndices!.length,
      );

  AudioPlayerHandlerImpl() {
    _idleTimer = RestartableTimer(const Duration(minutes: 10), () {
      if (_player?.playing ?? false) {
        stop();
      }
    });
    _idleTimer!.cancel();
    _init();
  }

  Future<void> _init() async {
    Logger.root.info('starting audio service');
    preferredCompactNotificationButtons = Hive.box('settings')
            .get('preferredCompactNotificationButtons', defaultValue: [1, 2, 3])
        as List<int>;
    if (preferredCompactNotificationButtons.length > 3) {
      preferredCompactNotificationButtons = [1, 2, 3];
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    await startService();

    await startBackgroundProcessing();

    speed.debounceTime(const Duration(milliseconds: 250)).listen((speed) {
      playbackState.add(playbackState.value.copyWith(speed: speed));
    });

    preferredQuality = Hive.box('settings')
        .get('streamingQuality', defaultValue: '96 kbps')
        .toString();
    resetOnSkip =
        Hive.box('settings').get('resetOnSkip', defaultValue: true) as bool;
    cacheSong =
        Hive.box('settings').get('cacheSong', defaultValue: true) as bool;
    recommend =
        Hive.box('settings').get('autoplay', defaultValue: true) as bool;
    loadStart =
        Hive.box('settings').get('loadStart', defaultValue: true) as bool;

    mediaItem.whereType<MediaItem>().listen((item) {
      if (count != null) {
        count = count! - 1;
        if (count! <= 0) {
          count = null;
          stop();
        }
      }

      if (item.artUri.toString().startsWith('http')) {
        addRecentlyPlayed(item);
        _recentSubject.add([item]);

        if (recommend && item.extras!['autoplay'] as bool) {
          final List<MediaItem> mediaQueue = queue.value;
          final int index = mediaQueue.indexOf(item);
          final int queueLength = mediaQueue.length;
          if (queueLength - index < 5) {
            Logger.root.info('less than 5 songs remaining, adding more songs');
            Future.delayed(const Duration(seconds: 1), () async {
              if (item == mediaItem.value) {
                if (item.extras?['language'] != 'YouTube') {
                  final List value = await SaavnAPI().getReco(item.id);
                  value.shuffle();
                  // final List value = await SaavnAPI().getRadioSongs(
                  //     stationId: stationId!, count: queueLength - index - 20);

                  for (int i = 0; i < value.length; i++) {
                    final element = MediaItemConverter.mapToMediaItem(
                      value[i] as Map,
                      addedByAutoplay: true,
                    );
                    if (!mediaQueue.contains(element)) {
                      addQueueItem(element);
                    }
                  }
                } else {
                  final res = await YtMusicService()
                      .getWatchPlaylist(videoId: item.id, limit: 5);

                  Logger.root.info('Received recommendations: $res');
                  refreshLinks.addAll(res);
                  if (!jobRunning) {
                    refreshJob();
                  }
                }
              }
            });
          }
        }
      }
    });

    Rx.combineLatest4<int?, List<MediaItem>, bool, List<int>?, MediaItem?>(
        _player!.currentIndexStream,
        queue,
        _player!.shuffleModeEnabledStream,
        _player!.shuffleIndicesStream,
        (index, queue, shuffleModeEnabled, shuffleIndices) {
      final queueIndex = getQueueIndex(
        index,
        shuffleIndices,
        shuffleModeEnabled: shuffleModeEnabled,
      );
      return (queueIndex != null && queueIndex < queue.length)
          ? queue[queueIndex]
          : null;
    }).whereType<MediaItem>().distinct().listen(mediaItem.add);

    // Propagate all events from the audio player to AudioService clients.
    _player!.playbackEventStream.listen(_broadcastState);

    playbackState
        .map((state) => state.bufferedPosition)
        .distinct()
        .listen(_bufferedChangeEvent);

    _player!.shuffleModeEnabledStream
        .listen((enabled) => _broadcastState(_player!.playbackEvent));

    _player!.loopModeStream
        .listen((event) => _broadcastState(_player!.playbackEvent));

    _player!.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        stop();
        _player!.seek(Duration.zero, index: 0);
      }
    });
    // Broadcast the current queue.
    _effectiveSequence
        .map(
          (sequence) =>
              sequence.map((source) => _mediaItemExpando[source]!).toList(),
        )
        .pipe(queue);
    try {
      if (loadStart) {
        final List lastQueueList = await Hive.box('cache')
            .get('lastQueue', defaultValue: [])?.toList() as List;

        final int lastIndex =
            await Hive.box('cache').get('lastIndex', defaultValue: 0) as int;

        final int lastPos =
            await Hive.box('cache').get('lastPos', defaultValue: 0) as int;

        if (lastQueueList
                .isNotEmpty /*&&
            lastQueueList.first['language'] != 'YouTube'*/
            ) {
          final List<MediaItem> lastQueue = lastQueueList
              .map((e) => MediaItemConverter.mapToMediaItem(e as Map))
              .toList();
          if (lastQueue.isEmpty) {
            await _player!.setAudioSource(_playlist, preload: false);
          } else {
            await _playlist.addAll(_itemsToSources(lastQueue));
            try {
              await _player!.setAudioSource(
                _playlist,
                // commented out due to some bug in audio_service which causes app to freeze
                // instead manually seeking after audiosource initialised

                /*initialIndex: lastIndex,
                 initialPosition: Duration(seconds: lastPos),*/
              );
              if (lastIndex != 0 || lastPos > 0) {
                await _player!
                    .seek(Duration(seconds: lastPos), index: lastIndex);
              }
            } catch (e) {
              Logger.root.severe('Error while setting last audiosource', e);
              await _player!.setAudioSource(_playlist, preload: false);
            }
          }
        } else {
          await _player!.setAudioSource(_playlist, preload: false);
        }
      } else {
        await _player!.setAudioSource(_playlist, preload: false);
      }
    } catch (e) {
      Logger.root.severe('Error while loading last queue', e);
      await _player!.setAudioSource(_playlist, preload: false);
    }
    if (!jobRunning) {
      refreshJob();
    }
  }

  Future<void> refreshJob() async {
    jobRunning = true;
    while (refreshLinks.isNotEmpty) {
      addIdToRefreshIsolateProcessing(refreshLinks.removeAt(0));
    }
    jobRunning = false;
  }

  Future<void> refreshLink(Map newData) async {
    Logger.root.info('player | received new link for ${newData['title']}');

    Map result = {};

    await Hive.openBox('spoty2youtube');
    final spotYTlinks = Hive.box('spoty2youtube');

    final res = spotYTlinks.keys.firstWhere(
      (k) => spotYTlinks.get(k) == newData['id'],
      orElse: () => null,
    );
    if (res == null) {
      await callSpotifyFunction(
        function: (String accessToken) async => {
          result = await SpotifyApi().fetchSearchResults(
            accessToken,
            searchQuery:
                "${newData['title']} ${newData['artist']} ${newData['album']}",
            count: 1,
          ),
        },
      );
    } else {
      await callSpotifyFunction(
        function: (String accessToken) async => {
          result['tracks'] = [
            await SpotifyApi().getTrackDetails(
              accessToken,
              res.toString(),
            ),
          ],
        },
      );
    }

    final List artists = [];
    final List artistsId = [];
    final song = result['tracks'].first;
    for (final artist in song['artists'] as List) {
      artists.add(artist['name']);
      artistsId.add(artist['id']);
    }

    newData['image'] = (song['album']['images'] as List)[0]['url'];
    newData['album_id'] = song['album']['id'];
    newData['spotify_artist_id'] = artistsId;
    newData['perma_url'] = song['external_urls']['spotify'];
    newData['subtitle'] = artists.join(', ');
    newData['album'] = song['album']['name'];
    newData['artist'] = artists.join(', ');

    final MediaItem newItem = MediaItemConverter.mapToMediaItem(newData);
    addQueueItem(newItem);
  }

  AudioSource? _itemToSource(MediaItem mediaItem) {
    AudioSource? audioSource;

    if (mediaItem.artUri.toString().startsWith('file:')) {
      audioSource =
          AudioSource.uri(Uri.file(mediaItem.extras!['url'].toString()));
    } else {
      if (downloadsBox.containsKey(mediaItem.id) && useDown) {
        //TODO: Add search in the cache folder to also use cached songs not only downloads
        audioSource = AudioSource.uri(
          Uri.file(
            (downloadsBox.get(mediaItem.id) as Map)['path'].toString(),
          ),
          tag: mediaItem.id,
        );
      } else {
        if (mediaItem.extras?['language'] == 'YouTube') {
          final int expiredAt =
              int.parse((mediaItem.extras!['expire_at'] ?? '0').toString());
          if ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 350 >
              expiredAt) {
            // Logger.root.info(
            //   'player | youtube link expired for ${mediaItem.title}, searching cache',
            // );
            if (Hive.box('ytlinkcache').containsKey(mediaItem.id)) {
              final Map cachedData =
                  Hive.box('ytlinkcache').get(mediaItem.id) as Map;
              final int cachedExpiredAt =
                  int.parse(cachedData['expire_at'].toString());
              if ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 350 >
                  cachedExpiredAt) {
                Logger.root.info(
                  'youtube link expired for ${mediaItem.title}, refreshing',
                );
                refreshLinks.add(mediaItem.id);
                if (!jobRunning) {
                  refreshJob();
                }
              } else {
                Logger.root.info(
                  'youtube link found in cache for ${mediaItem.title}',
                );
                if (cacheSong) {
                  audioSource = LockCachingAudioSource(
                    Uri.parse(cachedData['url'].toString()),
                    cacheFile: File(
                      path.joinAll([
                        MyApp.temporaryPath,
                        'just_audio_cache',
                        'remote',
                        'cache',
                        '${sha256.convert(
                          utf8.encode(
                            mediaItem.id,
                          ),
                        )}',
                      ]),
                    ),
                    headers: {'range': 'bytes=0-'},
                  );
                } else {
                  audioSource =
                      AudioSource.uri(Uri.parse(cachedData['url'].toString()));
                }
                mediaItem.extras!['url'] = cachedData['url'];
                _mediaItemExpando[audioSource] = mediaItem;
                return audioSource;
              }
            } else {
              Logger.root.info(
                'youtube link not found in cache for ${mediaItem.title}, refreshing',
              );
              refreshLinks.add(mediaItem.id);
              if (!jobRunning) {
                refreshJob();
              }
            }
          } else {
            if (cacheSong) {
              audioSource = LockCachingAudioSource(
                Uri.parse(mediaItem.extras!['url'].toString()),
                cacheFile: File(
                  path.joinAll([
                    MyApp.temporaryPath,
                    'just_audio_cache',
                    'remote',
                    'cache',
                    '${sha256.convert(
                      utf8.encode(
                        mediaItem.id,
                      ),
                    )}',
                  ]),
                ),
                headers: {'range': 'bytes=0-'},
              );
            } else {
              audioSource = AudioSource.uri(
                Uri.parse(mediaItem.extras!['url'].toString()),
              );
            }
            _mediaItemExpando[audioSource] = mediaItem;
            return audioSource;
          }
        } else {
          if (cacheSong) {
            audioSource = LockCachingAudioSource(
              Uri.parse(
                mediaItem.extras!['url'].toString().replaceAll(
                      '_96.',
                      "_${preferredQuality.replaceAll(' kbps', '')}.",
                    ),
              ),
              cacheFile: File(
                path.joinAll([
                  MyApp.temporaryPath,
                  'just_audio_cache',
                  'remote',
                  'cache',
                  '${sha256.convert(
                    utf8.encode(
                      mediaItem.id,
                    ),
                  )}',
                ]),
              ),
              headers: {'range': 'bytes=0-'},
            );
          } else {
            audioSource = AudioSource.uri(
              Uri.parse(
                mediaItem.extras!['url'].toString().replaceAll(
                      '_96.',
                      "_${preferredQuality.replaceAll(' kbps', '')}.",
                    ),
              ),
            );
          }
        }
      }
    }
    if (audioSource != null) {
      _mediaItemExpando[audioSource] = mediaItem;
    }
    return audioSource;
  }

  List<AudioSource> _itemsToSources(List<MediaItem> mediaItems) {
    preferredQuality = Hive.box('settings')
        .get('streamingQuality', defaultValue: '96 kbps')
        .toString();
    cacheSong =
        Hive.box('settings').get('cacheSong', defaultValue: true) as bool;
    useDown = Hive.box('settings').get('useDown', defaultValue: true) as bool;
    return mediaItems.map(_itemToSource).whereType<AudioSource>().toList();
  }

  @override
  Future<void> onTaskRemoved() async {
    final bool stopForegroundService = Hive.box('settings')
        .get('stopForegroundService', defaultValue: false) as bool;
    if (stopForegroundService) {
      await stop();
    }
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.recentRootId:
        return _recentSubject.value;
      default:
        return queue.value;
    }
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    switch (parentMediaId) {
      case AudioService.recentRootId:
        final stream = _recentSubject.map((_) => <String, dynamic>{});
        return _recentSubject.hasValue
            ? stream.shareValueSeeded(<String, dynamic>{})
            : stream.shareValue();
      default:
        return Stream.value(queue.value)
            .map((_) => <String, dynamic>{})
            .shareValue();
    }
  }

  Future<void> startService() async {
    final bool withPipeline =
        Hive.box('settings').get('supportEq', defaultValue: false) as bool;
    if (withPipeline && Platform.isAndroid) {
      Logger.root.info('starting with eq pipeline');
      final AudioPipeline pipeline = AudioPipeline(
        androidAudioEffects: [
          _equalizer,
        ],
      );
      _player = AudioPlayer(
        audioPipeline: pipeline,
      );

      // Enable equalizer if used earlier
      final eqValue = Hive.box('settings').get('setEqualizer') as bool;
      _equalizer.setEnabled(eqValue);

      // set equalizer params & bands
      _equalizerParams ??= await _equalizer.parameters;
      final List<AndroidEqualizerBand> bands = _equalizerParams!.bands;
      bands.map(
        (e) {
          final gain =
              Hive.box('settings').get('equalizerBand${e.index}') as double;
          _equalizerParams!.bands[e.index].setGain(gain);
        },
      );
    } else {
      Logger.root.info('starting without eq pipeline');
      _player = AudioPlayer();
    }
  }

  Future<void> addRecentlyPlayed(MediaItem mediaitem) async {
    Logger.root.info('adding ${mediaitem.id} to recently played');
    List recentList = await Hive.box('cache')
        .get('recentSongs', defaultValue: [])?.toList() as List;

    final Map songStats =
        await Hive.box('stats').get(mediaitem.id, defaultValue: {}) as Map;

    final Map mostPlayed =
        await Hive.box('stats').get('mostPlayed', defaultValue: {}) as Map;

    songStats['lastPlayed'] = DateTime.now().millisecondsSinceEpoch;
    songStats['playCount'] =
        songStats['playCount'] == null ? 1 : songStats['playCount'] + 1;
    songStats['isYoutube'] = mediaitem.extras?['language'] == 'YouTube';
    songStats['title'] = mediaitem.title;
    songStats['artist'] = mediaitem.artist;
    songStats['album'] = mediaitem.album;
    songStats['id'] = mediaitem.id;
    Hive.box('stats').put(mediaitem.id, songStats);
    if ((songStats['playCount'] as int) >
        (mostPlayed['playCount'] as int? ?? 0)) {
      Hive.box('stats').put('mostPlayed', songStats);
    }
    Logger.root.info('adding ${mediaitem.id} data to stats');

    final Map item = MediaItemConverter.mediaItemToMap(mediaitem);
    recentList.insert(0, item);

    final jsonList = recentList.map((item) => jsonEncode(item)).toList();
    final uniqueJsonList = jsonList.toSet().toList();
    recentList = uniqueJsonList.map((item) => jsonDecode(item)).toList();

    if (recentList.length > 30) {
      recentList = recentList.sublist(0, 30);
    }
    Hive.box('cache').put('recentSongs', recentList);
  }

  Future<void> addLastQueue(List<MediaItem> queue) async {
    //if (queue.first.extras?['language'] != 'YouTube') {
    Logger.root.info('saving last queue');
    final lastQueue =
        queue.map((item) => MediaItemConverter.mediaItemToMap(item)).toList();
    Hive.box('cache').put('lastQueue', lastQueue);
    //}
  }

  Future<void> skipToMediaItem(String id) async {
    final index = queue.value.indexWhere((item) => item.id == id);
    _player!.seek(
      Duration.zero,
      index:
          _player!.shuffleModeEnabled ? _player!.shuffleIndices![index] : index,
    );
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final res = _itemToSource(mediaItem);
    if (res != null) {
      await _playlist.add(res);
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    await _playlist.addAll(_itemsToSources(mediaItems));
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    final res = _itemToSource(mediaItem);
    if (res != null) {
      await _playlist.insert(index, res);
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    await _playlist.clear();
    await _playlist.addAll(_itemsToSources(newQueue));
    addLastQueue(newQueue);
    // stationId = '';
    // stationNames = newQueue.map((e) => e.id).toList();
    // SaavnAPI()
    //     .createRadio(names: stationNames, stationType: stationType)
    //     .then((value) async {
    //   stationId = value;
    //   final List songsList = await SaavnAPI()
    //       .getRadioSongs(stationId: stationId!, count: 20 - newQueue.length);

    //   for (int i = 0; i < songsList.length; i++) {
    //     final element = MediaItemConverter.mapToMediaItem(
    //       songsList[i] as Map,
    //       addedByAutoplay: true,
    //     );
    //     if (!queue.value.contains(element)) {
    //       addQueueItem(element);
    //     }
    //   }
    // });
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    final index = queue.value.indexWhere((item) => item.id == mediaItem.id);
    _mediaItemExpando[_player!.sequence![index]] = mediaItem;
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = queue.value.indexOf(mediaItem);
    await _playlist.removeAt(index);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    await _playlist.removeAt(index);
  }

  @override
  Future<void> moveQueueItem(int currentIndex, int newIndex) async {
    await _playlist.move(currentIndex, newIndex);
  }

  @override
  Future<void> skipToNext() => _player!.seekToNext();

  /// This is called when the user presses the "like" button.
  @override
  Future<void> fastForward() async {
    if (mediaItem.value?.id != null) {
      addItemToPlaylist('Favorite Songs', mediaItem.value!);
      _broadcastState(_player!.playbackEvent);
    }
  }

  @override
  Future<void> rewind() async {
    if (mediaItem.value?.id != null) {
      removeLiked(mediaItem.value!.id);
      _broadcastState(_player!.playbackEvent);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    resetOnSkip =
        Hive.box('settings').get('resetOnSkip', defaultValue: true) as bool;
    if (resetOnSkip) {
      if ((_player?.position.inSeconds ?? 5) <= 5) {
        _player!.seekToPrevious();
      } else {
        _player!.seek(Duration.zero);
      }
    } else {
      _player!.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playlist.children.length) return;

    _player!.seek(
      Duration.zero,
      index:
          _player!.shuffleModeEnabled ? _player!.shuffleIndices![index] : index,
    );
  }

  @override
  Future<void> play() => _player!.play();

  @override
  Future<void> pause() async {
    _player!.pause();
    await Hive.box('cache').put('lastIndex', _player!.currentIndex);
    await Hive.box('cache').put('lastPos', _player!.position.inSeconds);
  }

  @override
  Future<void> seek(Duration position) => _player!.seek(position);

  @override
  Future<void> stop() async {
    await _player!.stop();
    await playbackState.firstWhere(
      (state) => state.processingState == AudioProcessingState.idle,
    );
    await Hive.box('cache').put('lastIndex', _player!.currentIndex);
    await Hive.box('cache').put('lastPos', _player!.position.inSeconds);
  }

  @override
  Future customAction(String name, [Map<String, dynamic>? extras]) {
    if (name == 'sleepTimer') {
      _sleepTimer?.cancel();
      if (extras?['time'] != null &&
          extras!['time'].runtimeType == int &&
          extras['time'] > 0 as bool) {
        _sleepTimer = Timer(Duration(minutes: extras['time'] as int), () {
          stop();
        });
      }
    }
    if (name == 'sleepCounter') {
      if (extras?['count'] != null &&
          extras!['count'].runtimeType == int &&
          extras['count'] > 0 as bool) {
        count = extras['count'] as int;
      }
    }

    if (name == 'setBandGain') {
      final bandIdx = extras!['band'] as int;
      final gain = extras['gain'] as double;
      _equalizerParams!.bands[bandIdx].setGain(gain);
    }

    if (name == 'setEqualizer') {
      _equalizer.setEnabled(extras!['value'] as bool);
    }

    if (name == 'fastForward') {
      try {
        const stepInterval = Duration(seconds: 10);
        Duration newPosition = _player!.position + stepInterval;
        if (newPosition < Duration.zero) newPosition = Duration.zero;
        if (newPosition > _player!.duration!) newPosition = _player!.duration!;
        _player!.seek(newPosition);
      } catch (e) {
        Logger.root.severe('Error in fastForward', e);
      }
    }

    if (name == 'rewind') {
      try {
        const stepInterval = Duration(seconds: 10);
        Duration newPosition = _player!.position - stepInterval;
        if (newPosition < Duration.zero) newPosition = Duration.zero;
        if (newPosition > _player!.duration!) newPosition = _player!.duration!;
        _player!.seek(newPosition);
      } catch (e) {
        Logger.root.severe('Error in rewind', e);
      }
    }

    if (name == 'getEqualizerParams') {
      return getEqParms();
    }

    if (name == 'refreshLink') {
      if (extras?['newData'] != null) {
        refreshLink(extras!['newData'] as Map);
      }
    }

    if (name == 'skipToMediaItem') {
      skipToMediaItem(extras!['id'].toString());
    }
    return super.customAction(name, extras);
  }

  Future<Map> getEqParms() async {
    _equalizerParams ??= await _equalizer.parameters;
    final List<AndroidEqualizerBand> bands = _equalizerParams!.bands;
    final List<Map> bandList = bands
        .map(
          (e) => {
            'centerFrequency': e.centerFrequency,
            'gain': e.gain,
            'index': e.index,
          },
        )
        .toList();

    return {
      'maxDecibels': _equalizerParams!.maxDecibels,
      'minDecibels': _equalizerParams!.minDecibels,
      'bands': bandList,
    };
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    final enabled = mode == AudioServiceShuffleMode.all;
    if (enabled) {
      await _player!.shuffle();
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: mode));
    await _player!.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    await _player!.setLoopMode(LoopMode.values[repeatMode.index]);
  }

  @override
  Future<void> setSpeed(double speed) async {
    this.speed.add(speed);
    await _player!.setSpeed(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume.add(volume);
    await _player!.setVolume(volume);
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        _handleMediaActionPressed();
      case MediaButton.next:
        await skipToNext();
      case MediaButton.previous:
        await skipToPrevious();
    }
  }

  late BehaviorSubject<int> _tappedMediaActionNumber;
  Timer? _timer;

  void _handleMediaActionPressed() {
    if (_timer == null) {
      _tappedMediaActionNumber = BehaviorSubject.seeded(1);
      _timer = Timer(const Duration(milliseconds: 800), () {
        final tappedNumber = _tappedMediaActionNumber.value;
        switch (tappedNumber) {
          case 1:
            if (playbackState.value.playing) {
              pause();
            } else {
              play();
            }
          case 2:
            skipToNext();
          case 3:
            skipToPrevious();
          default:
            break;
        }
        _tappedMediaActionNumber.close();
        _timer!.cancel();
        _timer = null;
      });
    } else {
      final current = _tappedMediaActionNumber.value;
      _tappedMediaActionNumber.add(current + 1);
    }
  }

  /// Broadcasts the current state to all clients.
  void _broadcastState(PlaybackEvent event) {
    final playing = _player!.playing;
    if (!playing) {
      if (_idleTimer != null) {
        _idleTimer!.reset();
      }
    } else {
      if (_idleTimer != null) {
        _idleTimer!.cancel();
      }
    }
    bool liked = false;
    if (mediaItem.value != null) {
      liked = checkPlaylist('Favorite Songs', mediaItem.value!.id);
    }
    final queueIndex = getQueueIndex(
      event.currentIndex,
      _player!.shuffleIndices,
      shuffleModeEnabled: _player!.shuffleModeEnabled,
    );
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (liked) MediaControl.rewind else MediaControl.fastForward,
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          // workaround to add like button
          //MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: preferredCompactNotificationButtons,
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player!.processingState]!,
        playing: playing,
        updatePosition: _player!.position,
        bufferedPosition: _player!.bufferedPosition,
        speed: _player!.speed,
        queueIndex: queueIndex,
      ),
    );
  }

  Future<void> _bufferedChangeEvent(Duration event) async {
    getQueueIndex(
      _player!.currentIndex,
      _player!.shuffleIndices,
      shuffleModeEnabled: _player!.shuffleModeEnabled,
    );

    /*if (queueIndex != null && queue.value.isNotEmpty) {
      final cacheFile = File(
        path.joinAll([
          MyApp.temporaryPath,
          'just_audio_cache',
          'remote',
          '${sha256.convert(
            utf8.encode(
              queue.value.elementAt(queueIndex).id,
            ),
          )}',
        ]),
      );

      if (cacheFile.existsSync() &&
          !downloadsBox.containsKey(queue.value.elementAt(queueIndex).id)) {
        downloadsBox.put(
          queue.value.elementAt(queueIndex).id,
          {},
        );
        final preferredDownloadQuality = Hive.box('settings')
            .get('ytDownloadQuality', defaultValue: 'High') as String;
        String filepath2 = '';
        await File('${cacheFile.path}.jpg')
            .create(recursive: true)
            .then((value) => filepath2 = value.path);

        Map lyrics = {};
        final downloadLyrics = Hive.box('settings')
            .get('downloadLyrics', defaultValue: true) as bool;

        final songMap = MediaItemConverter.mediaItemToMap(
          queue.value.elementAt(queueIndex),
        );

        final client = HttpClient();
        final HttpClientRequest request2 =
            await client.getUrl(Uri.parse(songMap['image'].toString()));
        final HttpClientResponse response2 = await request2.close();
        final bytes2 = await consolidateHttpClientResponseBytes(response2);

        final File file2 = File(filepath2);
        await file2.writeAsBytes(bytes2);

        try {
          Logger.root.info('Checking if lyrics required');
          lyrics = downloadLyrics
              ? await Lyrics.getLyrics(
                  id: songMap['perma_url'].toString().split('/').last,
                  title: songMap['title'].toString(),
                  artist: songMap['artist'].toString(),
                  saavnHas: songMap['has_lyrics'] == 'false',
                )
              : {};
        } catch (e) {
          Logger.root.severe('Error fetching lyrics: $e');
        }

        final songData = {
          'id': songMap['id'].toString(),
          'title': songMap['title'].toString(),
          'subtitle': songMap['subtitle'].toString(),
          'artist': songMap['artist'].toString(),
          'albumArtist': songMap['album_artist']?.toString() ??
              songMap['artist']?.toString().split(', ')[0],
          'album': songMap['album'].toString(),
          'genre': songMap['language'].toString(),
          'year': songMap['year'].toString(),
          'lyrics': lyrics,
          'duration': songMap['duration'],
          'release_date': songMap['release_date'].toString(),
          'album_id': songMap['album_id'].toString(),
          'perma_url': songMap['perma_url'].toString(),
          'quality': preferredDownloadQuality,
          'path': cacheFile.path,
          'image': filepath2,
          'image_url': songMap['image'].toString(),
          'from_yt': songMap['language'].toString() == 'YouTube',
          'dateAdded': DateTime.now().toString(),
        };

        downloadsBox.put(
          queue.value.elementAt(queueIndex).id,
          songData,
        );
        try {
          final PlayScreen player = GetIt.I<PlayScreen>();
          player.refresh();
        } on Exception {
          /*If exception means player was not open so we don't care*/
        }
      }
    }*/
  }
}
