import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:soundal/APIs/spotify_api.dart';
import 'package:soundal/CustomWidgets/gradient_containers.dart';
import 'package:soundal/Helpers/countrycodes.dart';
import 'package:soundal/Helpers/logging.dart';
import 'package:soundal/Helpers/spotify_helper.dart';
import 'package:soundal/main.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  TextEditingController controller = TextEditingController();
  SpotifyApi spotifyApi = SpotifyApi();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future _addUserData(String name, String userId) async {
    await Hive.box('settings').put('name', name.trim());

    await Hive.box('settings').put('userId', userId);
  }

  Future<void> scrapData({bool signIn = false}) async {
    final bool spotifySigned =
        Hive.box('settings').get('spotifySigned', defaultValue: false) as bool;

    if (!spotifySigned && !signIn) {
      return;
    }
    final String? accessToken = await retriveAccessToken();
    if (accessToken == null) {
      Logger.root.info('no access token launching spotify auth url');
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
            Logger.root.info('received spotify auth code: $code');
            Hive.box('settings').put('spotifyAppCode', code);
            final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
            final List<String> data =
                await spotifyApi.getAccessToken(code: code);
            if (data.isNotEmpty) {
              Hive.box('settings').put('spotifyAccessToken', data[0]);
              Hive.box('settings').put('spotifyRefreshToken', data[1]);
              Hive.box('settings').put('spotifySigned', true);
              Hive.box('settings').put(
                'spotifyTokenExpireAt',
                currentTime + int.parse(data[2]),
              );
              final String? accessToken = await retriveAccessToken();
              if (accessToken != null) {
                Logger.root
                    .info('spotify access token retrieved: $accessToken');
                final userDetails =
                    await SpotifyApi().getUserDetails(accessToken);
                final String name =
                    userDetails['display_name'].split(' ')[0] as String;
                final String country =
                    ConstantCodes.countryCodes.keys.firstWhere(
                  (k) =>
                      ConstantCodes.countryCodes[k] ==
                      userDetails['country'].toLowerCase(),
                  orElse: () => '',
                );

                Logger.root.info('user country: $country');
                final String language =
                    ConstantCodes.languageCodes.keys.firstWhere(
                  (k) =>
                      ConstantCodes.languageCodes[k] ==
                      userDetails['country'].toLowerCase(),
                  orElse: () => 'English',
                );

                Logger.root.info('user language: $language');
                Hive.box('settings').put('region', country);
                _addUserData(
                  name,
                  userDetails['id'] as String,
                );

                MyApp.of(context).setLocale(
                  Locale.fromSubtags(
                    languageCode:
                        userDetails['country'].toLowerCase().toString(),
                  ),
                );
                Hive.box('settings').put('lang', language);
                Navigator.pushReplacementNamed(context, '/');
              } else {
                Logger.root.severe(
                    'token received but retriveAccessToken returned no token');
              }
            }
          } else {
            Logger.root.info('spotify auth contained no auth code');
          }
        },
      );
    } else {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientContainer(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: MediaQuery.of(context).size.width / 1.85,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width,
                  child: const Image(
                    image: AssetImage(
                      'assets/icon-white-trans.png',
                    ),
                  ),
                ),
              ),
              const GradientContainer(
                child: null,
                opacity: true,
              ),
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(left: 30.0, right: 30.0),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Row(
                              children: [
                                RichText(
                                  text: TextSpan(
                                    text: 'Soundal\n',
                                    style: TextStyle(
                                      height: 0.97,
                                      fontSize: 80,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                    children: <TextSpan>[
                                      const TextSpan(
                                        text: 'Music',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 80,
                                          color: Colors.white,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 80,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.1,
                            ),
                            Column(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    await scrapData(signIn: true);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 10.0,
                                    ),
                                    height: 55.0,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10.0),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 5.0,
                                          offset: Offset(0.0, 3.0),
                                        )
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        AppLocalizations.of(context)!
                                            .signInSpotify,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
