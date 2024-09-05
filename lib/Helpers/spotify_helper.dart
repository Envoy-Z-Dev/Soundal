import 'package:app_links/app_links.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/Helpers/logging.dart';
import 'package:soundal/main.dart';
import 'package:url_launcher/url_launcher.dart';

//final spotifyQueue = Queue(delay: const Duration(milliseconds: 350));

Future<String?> retriveAccessToken() async {
  String? accessToken = Hive.box('settings')
      .get('spotifyAccessToken', defaultValue: null)
      ?.toString();
  String? refreshToken = Hive.box('settings')
      .get('spotifyRefreshToken', defaultValue: null)
      ?.toString();
  final double expiredAt = Hive.box('settings')
      .get('spotifyTokenExpireAt', defaultValue: 0.0) as double;

  if (accessToken == null || refreshToken == null) {
    return null;
  } else {
    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
    if ((currentTime + 60 * 5) >= expiredAt) {
      final List<String> data =
          await SpotifyApi().getAccessToken(refreshToken: refreshToken);
      if (data.isNotEmpty) {
        await Hive.box('settings').put('spotifySigned', true);
        accessToken = data[0];
        await Hive.box('settings').put('spotifyAccessToken', data[0]);
        if (data[1] != 'null') {
          refreshToken = data[1];
          await Hive.box('settings').put('spotifyRefreshToken', data[1]);
        }
        await Hive.box('settings')
            .put('spotifyTokenExpireAt', currentTime + double.parse(data[2]));
      } else {
        await Hive.box('settings').put('spotifySigned', false);
        accessToken = null;
        await Hive.box('settings').put('spotifyAccessToken', null);
        if (data[1] != 'null') {
          refreshToken = null;
          await Hive.box('settings').put('spotifyRefreshToken', null);
        }
        await Hive.box('settings').put('spotifyTokenExpireAt', 0);
      }
    }
    return accessToken;
  }
}

Future<void> callSpotifyFunction({
  required Function(String accessToken)? function,
  bool forceSign = true,
}) async {
  String? accessToken;
  try {
    accessToken = await retriveAccessToken();
  } on Exception {
    accessToken = null;
  }
  if (accessToken != null && function != null) {
    return MyApp.spotifyQueue.add(() async {
      Logger.root.info('Called callSpotifyFunction at: ${DateTime.now()}');
      return await function.call(accessToken!);
    });
  }
  if (accessToken == null && forceSign) {
    final spotifyApi = SpotifyApi();
    launchUrl(
      Uri.parse(
        spotifyApi.requestAuthorization(),
      ),
      mode: LaunchMode.externalApplication,
    );
    final appLinks = AppLinks();
    appLinks.allUriLinkStream.listen(
      (uri) async {
        final link = uri.toString();
        if (link.contains('code=')) {
          final code = link.split('code=')[1];
          Hive.box('settings').put('spotifyAppCode', code);
          final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
          final List<String> data = await spotifyApi.getAccessToken(code: code);
          if (data.isNotEmpty) {
            await Hive.box('settings').put('spotifyAccessToken', data[0]);
            await Hive.box('settings').put('spotifyRefreshToken', data[1]);
            await Hive.box('settings').put(
              'spotifyTokenExpireAt',
              currentTime + int.parse(data[2]),
            );
            await Hive.box('settings').put('spotifySigned', true);
            if (function != null) {
              return MyApp.spotifyQueue.add(() async {
                Logger.root
                    .info('Called callSpotifyFunction at: ${DateTime.now()}');
                return await function.call(data[0]);
              });
            }
          }
        }
      },
    );
  }
}
