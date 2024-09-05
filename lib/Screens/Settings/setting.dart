import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soundal/CustomWidgets/gradient_containers.dart';
import 'package:soundal/CustomWidgets/snackbar.dart';
import 'package:soundal/Helpers/backup_restore.dart';
import 'package:soundal/Helpers/config.dart';
import 'package:soundal/Helpers/countrycodes.dart';
import 'package:soundal/Helpers/github.dart';
import 'package:soundal/Helpers/picker.dart';
import 'package:soundal/Screens/Top Charts/top.dart' as top_screen;
import 'package:soundal/Services/ext_storage_provider.dart';
import 'package:soundal/main.dart';

class SettingPage extends StatefulWidget {
  final Function? callback;
  const SettingPage({this.callback});
  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage>
    with AutomaticKeepAliveClientMixin<SettingPage> {
  String? appVersion;
  final Box settingsBox = Hive.box('settings');
  final MyTheme currentTheme = GetIt.I<MyTheme>();
  String downloadPath = Hive.box('settings')
      .get('downloadPath', defaultValue: '/storage/emulated/0/Music') as String;
  String autoBackPath = Hive.box('settings').get(
    'autoBackPath',
    defaultValue: '/storage/emulated/0/Soundal/Backups',
  ) as String;
  final ValueNotifier<bool> includeOrExclude = ValueNotifier<bool>(
    Hive.box('settings').get('includeOrExclude', defaultValue: false) as bool,
  );
  List includedExcludedPaths = Hive.box('settings')
      .get('includedExcludedPaths', defaultValue: []) as List;
  List blacklistedHomeSections = Hive.box('settings')
      .get('blacklistedHomeSections', defaultValue: []) as List;
  String streamingQuality = Hive.box('settings')
      .get('streamingQuality', defaultValue: '96 kbps') as String;
  String ytQuality =
      Hive.box('settings').get('ytQuality', defaultValue: 'High') as String;
  String downloadQuality = Hive.box('settings')
      .get('downloadQuality', defaultValue: '320 kbps') as String;
  String ytDownloadQuality = Hive.box('settings')
      .get('ytDownloadQuality', defaultValue: 'High') as String;
  String lang =
      Hive.box('settings').get('lang', defaultValue: 'English') as String;
  String canvasColor =
      Hive.box('settings').get('canvasColor', defaultValue: 'Black') as String;
  String cardColor =
      Hive.box('settings').get('cardColor', defaultValue: 'Black') as String;
  String theme =
      Hive.box('settings').get('theme', defaultValue: 'Default') as String;
  Map userThemes =
      Hive.box('settings').get('userThemes', defaultValue: {}) as Map;
  String region =
      Hive.box('settings').get('region', defaultValue: 'Global') as String;
  bool useProxy =
      Hive.box('settings').get('useProxy', defaultValue: false) as bool;
  String themeColor =
      Hive.box('settings').get('themeColor', defaultValue: 'Orange') as String;
  int colorHue = Hive.box('settings').get('colorHue', defaultValue: 700) as int;
  int downFilename =
      Hive.box('settings').get('downFilename', defaultValue: 0) as int;
  List<String> languages = [
    'Hindi',
    'English',
    'Punjabi',
    'Tamil',
    'Telugu',
    'Marathi',
    'Gujarati',
    'Bengali',
    'Kannada',
    'Bhojpuri',
    'Malayalam',
    'Urdu',
    'Haryanvi',
    'Rajasthani',
    'Odia',
    'Assamese',
  ];
  List miniButtonsOrder = Hive.box('settings').get(
    'miniButtonsOrder',
    defaultValue: ['Like', 'Previous', 'Play/Pause', 'Next', 'Download'],
  ) as List;
  List preferredLanguage = Hive.box('settings')
      .get('preferredLanguage', defaultValue: ['English'])?.toList() as List;
  List preferredMiniButtons = Hive.box('settings').get(
    'preferredMiniButtons',
    defaultValue: ['Like', 'Play/Pause', 'Next'],
  )?.toList() as List;
  List<int> preferredCompactNotificationButtons = Hive.box('settings').get(
    'preferredCompactNotificationButtons',
    defaultValue: [1, 2, 3],
  ) as List<int>;
  final ValueNotifier<List> sectionsToShow = ValueNotifier<List>(
    Hive.box('settings').get(
      'sectionsToShow',
      defaultValue: ['Home', 'Top Charts', 'Library', 'Settings'],
    ) as List,
  );

  @override
  void initState() {
    main();
    super.initState();
  }

  @override
  bool get wantKeepAlive => sectionsToShow.value.contains('Settings');

  Future<void> main() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    appVersion = packageInfo.version;
    setState(
      () {},
    );
  }

  bool compareVersion(String latestVersion, String currentVersion) {
    bool update = false;
    final List<String> latestList = latestVersion.split('.');
    final List<String> currentList = currentVersion.split('.');

    for (int i = 0; i < latestList.length; i++) {
      try {
        if (int.parse(latestList[i]) > int.parse(currentList[i])) {
          update = true;
          break;
        }
      } catch (e) {
        break;
      }
    }

    return update;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      // backgroundColor: Colors.transparent,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            elevation: 0,
            stretch: true,
            pinned: true,
            title: Center(
              child: AppBar(
                title: Text(
                  AppLocalizations.of(context)!.settings,
                  style: TextStyle(
                    color: Theme.of(context).iconTheme.color,
                  ),
                ),
                centerTitle: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                automaticallyImplyLeading: false,
              ),
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.light
                ? Theme.of(context).colorScheme.secondary
                : null,
          ),
          SliverList(
            delegate: SliverChildListDelegate(
              [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    10.0,
                    10.0,
                    10.0,
                    10.0,
                  ),
                  child: GradientCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            15,
                            15,
                            15,
                            0,
                          ),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .musicPlayback,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .chartLocation,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .chartLocationSub,
                          ),
                          trailing: SizedBox(
                            width: 150,
                            child: Text(
                              region,
                              textAlign: TextAlign.end,
                            ),
                          ),
                          dense: true,
                          onTap: () async {
                            region = await SpotifyCountry()
                                .changeCountry(context: context);
                            setState(
                              () {},
                            );
                          },
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .streamQuality,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .streamQualitySub,
                          ),
                          onTap: () {},
                          trailing: DropdownButton(
                            value: ytQuality,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                            underline: const SizedBox(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(
                                  () {
                                    ytQuality = newValue;
                                    Hive.box('settings')
                                        .put('ytQuality', newValue);
                                  },
                                );
                              }
                            },
                            items: <String>['Low', 'High']
                                .map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                          dense: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .loadLast,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .loadLastSub,
                          ),
                          keyName: 'loadStart',
                          defaultValue: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .resetOnSkip,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .resetOnSkipSub,
                          ),
                          keyName: 'resetOnSkip',
                          defaultValue: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .enforceRepeat,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .enforceRepeatSub,
                          ),
                          keyName: 'enforceRepeat',
                          defaultValue: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .autoplay,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .autoplaySub,
                          ),
                          keyName: 'autoplay',
                          defaultValue: true,
                          isThreeLine: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .cacheSong,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .cacheSongSub,
                          ),
                          keyName: 'cacheSong',
                          defaultValue: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    10.0,
                    10.0,
                    10.0,
                    10.0,
                  ),
                  child: GradientCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            15,
                            15,
                            15,
                            0,
                          ),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .down,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downQuality,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downQualitySub,
                          ),
                          onTap: () {},
                          trailing: DropdownButton(
                            value: ytDownloadQuality,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                            underline: const SizedBox(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(
                                  () {
                                    ytDownloadQuality = newValue;
                                    Hive.box('settings')
                                        .put('ytDownloadQuality', newValue);
                                  },
                                );
                              }
                            },
                            items: <String>['Low', 'High']
                                .map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  value,
                                ),
                              );
                            }).toList(),
                          ),
                          dense: true,
                        ),
                        /*ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downLocation,
                          ),
                          subtitle: Text(downloadPath),
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                            onPressed: () async {
                              downloadPath =
                                  await ExtStorageProvider.getExtStorage(
                                        dirName: 'Music',
                                        writeAccess: true,
                                      ) ??
                                      '/storage/emulated/0/Music';
                              Hive.box('settings')
                                  .put('downloadPath', downloadPath);
                              setState(
                                () {},
                              );
                            },
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!
                                  .reset,
                            ),
                          ),
                          onTap: () async {
                            final String temp = await Picker.selectFolder(
                              context: context,
                              message: AppLocalizations.of(
                                context,
                              )!
                                  .selectDownLocation,
                            );
                            if (temp.trim() != '') {
                              downloadPath = temp;
                              Hive.box('settings').put('downloadPath', temp);
                              setState(
                                () {},
                              );
                            } else {
                              ShowSnackBar().showSnackBar(
                                context,
                                AppLocalizations.of(
                                  context,
                                )!
                                    .noFolderSelected,
                              );
                            }
                          },
                          dense: true,
                        ),*/
                        /*ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downFilename,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downFilenameSub,
                          ),
                          dense: true,
                          onTap: () {
                            showModalBottomSheet(
                              isDismissible: true,
                              backgroundColor: Colors.transparent,
                              context: context,
                              builder: (BuildContext context) {
                                return BottomGradientContainer(
                                  borderRadius: BorderRadius.circular(
                                    20.0,
                                  ),
                                  child: ListView(
                                    physics: const BouncingScrollPhysics(),
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      10,
                                      0,
                                      10,
                                    ),
                                    children: [
                                      CheckboxListTile(
                                        activeColor: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        title: Text(
                                          '${AppLocalizations.of(context)!.title} - ${AppLocalizations.of(context)!.artist}',
                                        ),
                                        value: downFilename == 0,
                                        selected: downFilename == 0,
                                        onChanged: (bool? val) {
                                          if (val ?? false) {
                                            downFilename = 0;
                                            settingsBox.put('downFilename', 0);
                                            Navigator.pop(context);
                                          }
                                        },
                                      ),
                                      CheckboxListTile(
                                        activeColor: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        title: Text(
                                          '${AppLocalizations.of(context)!.artist} - ${AppLocalizations.of(context)!.title}',
                                        ),
                                        value: downFilename == 1,
                                        selected: downFilename == 1,
                                        onChanged: (val) {
                                          if (val ?? false) {
                                            downFilename = 1;
                                            settingsBox.put('downFilename', 1);
                                            Navigator.pop(context);
                                          }
                                        },
                                      ),
                                      CheckboxListTile(
                                        activeColor: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        title: Text(
                                          AppLocalizations.of(context)!.title,
                                        ),
                                        value: downFilename == 2,
                                        selected: downFilename == 2,
                                        onChanged: (val) {
                                          if (val ?? false) {
                                            downFilename = 2;
                                            settingsBox.put('downFilename', 2);
                                            Navigator.pop(context);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),*/
                        /*BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .createAlbumFold,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .createAlbumFoldSub,
                          ),
                          keyName: 'createDownloadFolder',
                          isThreeLine: true,
                          defaultValue: true,
                        ),*/
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downLyrics,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .downLyricsSub,
                          ),
                          keyName: 'downloadLyrics',
                          defaultValue: true,
                          isThreeLine: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    10.0,
                    10.0,
                    10.0,
                    10.0,
                  ),
                  child: GradientCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            15,
                            15,
                            15,
                            0,
                          ),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .others,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .lang,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .langSub,
                          ),
                          onTap: () {},
                          trailing: DropdownButton(
                            value: lang,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                            underline: const SizedBox(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(
                                  () {
                                    lang = newValue;
                                    MyApp.of(context).setLocale(
                                      Locale.fromSubtags(
                                        languageCode: ConstantCodes
                                                .languageCodes[newValue] ??
                                            'en',
                                      ),
                                    );
                                    Hive.box('settings').put('lang', newValue);
                                  },
                                );
                              }
                            },
                            items: ConstantCodes.languageCodes.keys
                                .map<DropdownMenuItem<String>>((language) {
                              return DropdownMenuItem<String>(
                                value: language,
                                child: Text(
                                  language,
                                ),
                              );
                            }).toList(),
                          ),
                          dense: true,
                        ),
                        /*ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .includeExcludeFolder,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .includeExcludeFolderSub,
                          ),
                          dense: true,
                          onTap: () {
                            final GlobalKey<AnimatedListState> listKey =
                                GlobalKey<AnimatedListState>();
                            showModalBottomSheet(
                              isDismissible: true,
                              backgroundColor: Colors.transparent,
                              context: context,
                              builder: (BuildContext context) {
                                return BottomGradientContainer(
                                  borderRadius: BorderRadius.circular(
                                    20.0,
                                  ),
                                  child: AnimatedList(
                                    physics: const BouncingScrollPhysics(),
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      10,
                                      0,
                                      10,
                                    ),
                                    key: listKey,
                                    initialItemCount:
                                        includedExcludedPaths.length + 2,
                                    itemBuilder: (cntxt, idx, animation) {
                                      if (idx == 0) {
                                        return ValueListenableBuilder(
                                          valueListenable: includeOrExclude,
                                          builder: (
                                            BuildContext context,
                                            bool value,
                                            Widget? widget,
                                          ) {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: <Widget>[
                                                    ChoiceChip(
                                                      label: Text(
                                                        AppLocalizations.of(
                                                          context,
                                                        )!
                                                            .excluded,
                                                      ),
                                                      selectedColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .secondary
                                                              .withOpacity(0.2),
                                                      labelStyle: TextStyle(
                                                        color: !value
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                            : Theme.of(context)
                                                                .textTheme
                                                                .bodyLarge!
                                                                .color,
                                                        fontWeight: !value
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                      selected: !value,
                                                      onSelected:
                                                          (bool selected) {
                                                        includeOrExclude.value =
                                                            !selected;
                                                        settingsBox.put(
                                                          'includeOrExclude',
                                                          !selected,
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(
                                                      width: 5,
                                                    ),
                                                    ChoiceChip(
                                                      label: Text(
                                                        AppLocalizations.of(
                                                          context,
                                                        )!
                                                            .included,
                                                      ),
                                                      selectedColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .secondary
                                                              .withOpacity(0.2),
                                                      labelStyle: TextStyle(
                                                        color: value
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .secondary
                                                            : Theme.of(context)
                                                                .textTheme
                                                                .bodyLarge!
                                                                .color,
                                                        fontWeight: value
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                      selected: value,
                                                      onSelected:
                                                          (bool selected) {
                                                        includeOrExclude.value =
                                                            selected;
                                                        settingsBox.put(
                                                          'includeOrExclude',
                                                          selected,
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    left: 5.0,
                                                    top: 5.0,
                                                    bottom: 10.0,
                                                  ),
                                                  child: Text(
                                                    value
                                                        ? AppLocalizations.of(
                                                            context,
                                                          )!
                                                            .includedDetails
                                                        : AppLocalizations.of(
                                                            context,
                                                          )!
                                                            .excludedDetails,
                                                    textAlign: TextAlign.start,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      }
                                      if (idx == 1) {
                                        return ListTile(
                                          title: Text(
                                            AppLocalizations.of(context)!
                                                .addNew,
                                          ),
                                          leading: const Icon(
                                            CupertinoIcons.add,
                                          ),
                                          onTap: () async {
                                            final String temp =
                                                await Picker.selectFolder(
                                              context: context,
                                            );
                                            if (temp.trim() != '' &&
                                                !includedExcludedPaths
                                                    .contains(temp)) {
                                              includedExcludedPaths.add(temp);
                                              Hive.box('settings').put(
                                                'includedExcludedPaths',
                                                includedExcludedPaths,
                                              );
                                              listKey.currentState!.insertItem(
                                                includedExcludedPaths.length,
                                              );
                                            } else {
                                              if (temp.trim() == '') {
                                                Navigator.pop(context);
                                              }
                                              ShowSnackBar().showSnackBar(
                                                context,
                                                temp.trim() == ''
                                                    ? 'No folder selected'
                                                    : 'Already added',
                                              );
                                            }
                                          },
                                        );
                                      }

                                      return SizeTransition(
                                        sizeFactor: animation,
                                        child: ListTile(
                                          leading: const Icon(
                                            CupertinoIcons.folder,
                                          ),
                                          title: Text(
                                            includedExcludedPaths[idx - 2]
                                                .toString(),
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(
                                              CupertinoIcons.clear,
                                              size: 15.0,
                                            ),
                                            tooltip: 'Remove',
                                            onPressed: () {
                                              includedExcludedPaths
                                                  .removeAt(idx - 2);
                                              Hive.box('settings').put(
                                                'includedExcludedPaths',
                                                includedExcludedPaths,
                                              );
                                              listKey.currentState!.removeItem(
                                                idx,
                                                (context, animation) =>
                                                    Container(),
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),*/
                        /*ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .minAudioLen,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .minAudioLenSub,
                          ),
                          dense: true,
                          onTap: () {
                            showTextInputDialog(
                              context: context,
                              title: AppLocalizations.of(
                                context,
                              )!
                                  .minAudioAlert,
                              initialText: (Hive.box('settings')
                                          .get('minDuration', defaultValue: 10)
                                      as int)
                                  .toString(),
                              keyboardType: TextInputType.number,
                              onSubmitted: (String value) {
                                if (value.trim() == '') {
                                  value = '0';
                                }
                                Hive.box('settings')
                                    .put('minDuration', int.parse(value));
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),*/
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .liveSearch,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .liveSearchSub,
                          ),
                          keyName: 'liveSearch',
                          isThreeLine: false,
                          defaultValue: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .useDown,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .useDownSub,
                          ),
                          keyName: 'useDown',
                          isThreeLine: true,
                          defaultValue: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .getLyricsOnline,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .getLyricsOnlineSub,
                          ),
                          keyName: 'getLyricsOnline',
                          isThreeLine: true,
                          defaultValue: true,
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .supportEq,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .supportEqSub,
                          ),
                          keyName: 'supportEq',
                          isThreeLine: true,
                          defaultValue: false,
                        ),
                        /*BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .stopOnClose,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .stopOnCloseSub,
                          ),
                          isThreeLine: true,
                          keyName: 'stopForegroundService',
                          defaultValue: true,
                        ),*/
                        // const BoxSwitchTile(
                        //   title: Text('Remove Service from foreground when paused'),
                        //   subtitle: Text(
                        //       "If turned on, you can slide notification when paused to stop the service. But Service can also be stopped by android to release memory. If you don't want android to stop service while paused, turn it off\nDefault: On\n"),
                        //   isThreeLine: true,
                        //   keyName: 'stopServiceOnPause',
                        //   defaultValue: true,
                        // ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .checkUpdate,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .checkUpdateSub,
                          ),
                          keyName: 'checkUpdate',
                          isThreeLine: true,
                          defaultValue: false,
                        ),
                        /*BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .useProxy,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .useProxySub,
                          ),
                          keyName: 'useProxy',
                          defaultValue: false,
                          isThreeLine: true,
                          onChanged: (bool val, Box box) {
                            useProxy = val;
                            setState(
                              () {},
                            );
                          },
                        ),*/
                        Visibility(
                          visible: useProxy,
                          child: ListTile(
                            title: Text(
                              AppLocalizations.of(
                                context,
                              )!
                                  .proxySet,
                            ),
                            subtitle: Text(
                              AppLocalizations.of(
                                context,
                              )!
                                  .proxySetSub,
                            ),
                            dense: true,
                            trailing: Text(
                              '${Hive.box('settings').get("proxyIp")}:${Hive.box('settings').get("proxyPort")}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  final controller = TextEditingController(
                                    text: settingsBox.get('proxyIp').toString(),
                                  );
                                  final controller2 = TextEditingController(
                                    text:
                                        settingsBox.get('proxyPort').toString(),
                                  );
                                  return AlertDialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        10.0,
                                      ),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .ipAdd,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        TextField(
                                          autofocus: true,
                                          controller: controller,
                                        ),
                                        const SizedBox(
                                          height: 30,
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .port,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        TextField(
                                          autofocus: true,
                                          controller: controller2,
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : Colors.grey[700],
                                        ),
                                        onPressed: () {
                                          Navigator.pop(context);
                                        },
                                        child: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!
                                              .cancel,
                                        ),
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Theme.of(context)
                                                      .colorScheme
                                                      .secondary ==
                                                  Colors.white
                                              ? Colors.black
                                              : null,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                        ),
                                        onPressed: () {
                                          settingsBox.put(
                                            'proxyIp',
                                            controller.text.trim(),
                                          );
                                          settingsBox.put(
                                            'proxyPort',
                                            int.parse(
                                              controller2.text.trim(),
                                            ),
                                          );
                                          Navigator.pop(context);
                                          setState(
                                            () {},
                                          );
                                        },
                                        child: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!
                                              .ok,
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
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .clearCache,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .clearCacheSub,
                          ),
                          trailing: SizedBox(
                            height: 70.0,
                            width: 70.0,
                            child: Center(
                              child: FutureBuilder(
                                future: File(Hive.box('cache').path!).length(),
                                builder: (
                                  BuildContext context,
                                  AsyncSnapshot<int> snapshot,
                                ) {
                                  //TODO:add cache songs size
                                  if (snapshot.connectionState ==
                                      ConnectionState.done) {
                                    return Text(
                                      '${((snapshot.data ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB',
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          dense: true,
                          isThreeLine: true,
                          onTap: () async {
                            //TODO: clear all cached songs
                            Hive.box('cache').clear();
                            for (final file in Directory(
                              path.joinAll([
                                MyApp.temporaryPath,
                                'just_audio_cache',
                                'remote',
                                'cache',
                              ]),
                            ).listSync()) {
                              await file.delete(recursive: true);
                            }
                            setState(
                              () {},
                            );
                          },
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .shareLogs,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .shareLogsSub,
                          ),
                          onTap: () async {
                            final Directory tempDir =
                                await getTemporaryDirectory();
                            final files = <XFile>[
                              XFile('${tempDir.path}/logs/logs.txt'),
                            ];
                            Share.shareXFiles(files);
                          },
                          dense: true,
                          isThreeLine: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    10.0,
                    10.0,
                    10.0,
                    10.0,
                  ),
                  child: GradientCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            15,
                            15,
                            15,
                            0,
                          ),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .backNRest,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .createBack,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .createBackSub,
                          ),
                          dense: true,
                          onTap: () {
                            showModalBottomSheet(
                              backgroundColor: Colors.transparent,
                              context: context,
                              builder: (BuildContext context) {
                                final List playlistNames =
                                    Hive.box('settings').get(
                                  'playlistNames',
                                  defaultValue: ['Favorite Songs'],
                                ) as List;
                                if (!playlistNames.contains('Favorite Songs')) {
                                  playlistNames.insert(0, 'Favorite Songs');
                                  settingsBox.put(
                                    'playlistNames',
                                    playlistNames,
                                  );
                                }

                                final List<String> persist = [
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .settings,
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .playlists,
                                ];

                                final List<String> checked = [
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .settings,
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .downs,
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .playlists,
                                ];

                                final List<String> items = [
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .settings,
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .playlists,
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .downs,
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .cache,
                                ];

                                final Map<String, List> boxNames = {
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .settings: ['settings'],
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .cache: ['cache'],
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .downs: ['downloads'],
                                  AppLocalizations.of(
                                    context,
                                  )!
                                      .playlists: playlistNames,
                                };
                                return StatefulBuilder(
                                  builder: (
                                    BuildContext context,
                                    StateSetter setStt,
                                  ) {
                                    return BottomGradientContainer(
                                      borderRadius: BorderRadius.circular(
                                        20.0,
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: ListView.builder(
                                              physics:
                                                  const BouncingScrollPhysics(),
                                              shrinkWrap: true,
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                0,
                                                10,
                                                0,
                                                10,
                                              ),
                                              itemCount: items.length,
                                              itemBuilder: (context, idx) {
                                                return CheckboxListTile(
                                                  activeColor: Theme.of(context)
                                                      .colorScheme
                                                      .secondary,
                                                  checkColor: Theme.of(context)
                                                              .colorScheme
                                                              .secondary ==
                                                          Colors.white
                                                      ? Colors.black
                                                      : null,
                                                  value: checked.contains(
                                                    items[idx],
                                                  ),
                                                  title: Text(
                                                    items[idx],
                                                  ),
                                                  onChanged: persist
                                                          .contains(items[idx])
                                                      ? null
                                                      : (bool? value) {
                                                          value!
                                                              ? checked.add(
                                                                  items[idx],
                                                                )
                                                              : checked.remove(
                                                                  items[idx],
                                                                );
                                                          setStt(
                                                            () {},
                                                          );
                                                        },
                                                );
                                              },
                                            ),
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .secondary,
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                },
                                                child: Text(
                                                  AppLocalizations.of(
                                                    context,
                                                  )!
                                                      .cancel,
                                                ),
                                              ),
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .secondary,
                                                ),
                                                onPressed: () {
                                                  createBackup(
                                                    context,
                                                    checked,
                                                    boxNames,
                                                  );
                                                  Navigator.pop(context);
                                                },
                                                child: Text(
                                                  AppLocalizations.of(
                                                    context,
                                                  )!
                                                      .ok,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .restore,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .restoreSub,
                          ),
                          dense: true,
                          onTap: () async {
                            await restore(context);
                            currentTheme.refresh();
                          },
                        ),
                        BoxSwitchTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .autoBack,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .autoBackSub,
                          ),
                          keyName: 'autoBackup',
                          defaultValue: false,
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .autoBackLocation,
                          ),
                          subtitle: Text(autoBackPath),
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                            onPressed: () async {
                              autoBackPath =
                                  await ExtStorageProvider.getExtStorage(
                                        dirName: 'Soundal/Backups',
                                        writeAccess: true,
                                      ) ??
                                      '/storage/emulated/0/Soundal/Backups';
                              Hive.box('settings')
                                  .put('autoBackPath', autoBackPath);
                              setState(
                                () {},
                              );
                            },
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!
                                  .reset,
                            ),
                          ),
                          onTap: () async {
                            final String temp = await Picker.selectFolder(
                              context: context,
                              message: AppLocalizations.of(
                                context,
                              )!
                                  .selectBackLocation,
                            );
                            if (temp.trim() != '') {
                              autoBackPath = temp;
                              Hive.box('settings').put('autoBackPath', temp);
                              setState(
                                () {},
                              );
                            } else {
                              ShowSnackBar().showSnackBar(
                                context,
                                AppLocalizations.of(
                                  context,
                                )!
                                    .noFolderSelected,
                              );
                            }
                          },
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    10.0,
                    10.0,
                    10.0,
                    10.0,
                  ),
                  child: GradientCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            15,
                            15,
                            15,
                            0,
                          ),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .about,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .version,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .versionSub,
                          ),
                          onTap: () {
                            ShowSnackBar().showSnackBar(
                              context,
                              AppLocalizations.of(
                                context,
                              )!
                                  .checkingUpdate,
                              noAction: true,
                            );

                            GitHub.getLatestVersion().then(
                              (String latestVersion) async {
                                if (compareVersion(
                                  latestVersion,
                                  appVersion!,
                                )) {
                                  List? abis = await Hive.box('settings')
                                      .get('supportedAbis') as List?;

                                  if (abis == null) {
                                    final DeviceInfoPlugin deviceInfo =
                                        DeviceInfoPlugin();
                                    final AndroidDeviceInfo androidDeviceInfo =
                                        await deviceInfo.androidInfo;
                                    abis = androidDeviceInfo.supportedAbis;
                                    await Hive.box('settings')
                                        .put('supportedAbis', abis);
                                  }
                                  ShowSnackBar().showSnackBar(
                                    context,
                                    AppLocalizations.of(context)!
                                        .updateAvailable,
                                    duration: const Duration(seconds: 15),
                                    action: SnackBarAction(
                                      textColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      label:
                                          AppLocalizations.of(context)!.update,
                                      onPressed: () {
                                        Navigator.pop(context);
                                        /*launchUrl(
                                          Uri.parse(
                                            'https://sangwan5688.github.io/download/',
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        );*/
                                      },
                                    ),
                                  );
                                } else {
                                  ShowSnackBar().showSnackBar(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!
                                        .latest,
                                  );
                                }
                              },
                            );
                          },
                          trailing: Text(
                            'v$appVersion',
                            style: const TextStyle(fontSize: 12),
                          ),
                          dense: true,
                        ),
                        /*ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .shareApp,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .shareAppSub,
                          ),
                          onTap: () {
                            Share.share(
                              '${AppLocalizations.of(
                                context,
                              )!.shareAppText}: https://sangwan5688.github.io/',
                            );
                          },
                          dense: true,
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .likedWork,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .buyCoffee,
                          ),
                          dense: true,
                          onTap: () {
                            launchUrl(
                              Uri.parse(
                                'https://www.buymeacoffee.com/ankitsangwan',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .donateGpay,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .donateGpaySub,
                          ),
                          dense: true,
                          isThreeLine: true,
                          onTap: () {
                            const String upiUrl =
                                'upi://pay?pa=ankit.sangwan.5688@oksbi&pn=Soundal';
                            launchUrl(
                              Uri.parse(upiUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          onLongPress: () {
                            copyToClipboard(
                              context: context,
                              text: 'ankit.sangwan.5688@oksbi',
                              displayText: AppLocalizations.of(
                                context,
                              )!
                                  .upiCopied,
                            );
                          },
                          trailing: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                            onPressed: () {
                              copyToClipboard(
                                context: context,
                                text: 'ankit.sangwan.5688@oksbi',
                                displayText: AppLocalizations.of(
                                  context,
                                )!
                                    .upiCopied,
                              );
                            },
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!
                                  .copy,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .contactUs,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .contactUsSub,
                          ),
                          dense: true,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (BuildContext context) {
                                return SizedBox(
                                  height: 100,
                                  child: GradientContainer(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                MdiIcons.gmail,
                                              ),
                                              iconSize: 40,
                                              tooltip: AppLocalizations.of(
                                                context,
                                              )!
                                                  .gmail,
                                              onPressed: () {
                                                Navigator.pop(context);
                                                launchUrl(
                                                  Uri.parse(
                                                    'https://mail.google.com/mail/?extsrc=mailto&url=mailto%3A%3Fto%3Dsoundalyoucantescape%40gmail.com%26subject%3DRegarding%2520Mobile%2520App',
                                                  ),
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              },
                                            ),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .gmail,
                                            ),
                                          ],
                                        ),
                                        /*Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                MdiIcons.telegram,
                                              ),
                                              iconSize: 40,
                                              tooltip: AppLocalizations.of(
                                                context,
                                              )!
                                                  .tg,
                                              onPressed: () {
                                                Navigator.pop(context);
                                                launchUrl(
                                                  Uri.parse(
                                                    'https://t.me/joinchat/fHDC1AWnOhw0ZmI9',
                                                  ),
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              },
                                            ),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .tg,
                                            ),
                                          ],
                                        ),*/
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                MdiIcons.instagram,
                                              ),
                                              iconSize: 40,
                                              tooltip: AppLocalizations.of(
                                                context,
                                              )!
                                                  .insta,
                                              onPressed: () {
                                                Navigator.pop(context);
                                                launchUrl(
                                                  Uri.parse(
                                                    'https://instagram.com/sangwan5688',
                                                  ),
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              },
                                            ),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .insta,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .joinTg,
                          ),
                          subtitle: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .joinTgSub,
                          ),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (BuildContext context) {
                                return SizedBox(
                                  height: 100,
                                  child: GradientContainer(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        /*Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                MdiIcons.telegram,
                                              ),
                                              iconSize: 40,
                                              tooltip: AppLocalizations.of(
                                                context,
                                              )!
                                                  .tgGp,
                                              onPressed: () {
                                                Navigator.pop(context);
                                                launchUrl(
                                                  Uri.parse(
                                                    'https://t.me/joinchat/fHDC1AWnOhw0ZmI9',
                                                  ),
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              },
                                            ),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .tgGp,
                                            ),
                                          ],
                                        ),*/
                                        /*Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                MdiIcons.telegram,
                                              ),
                                              iconSize: 40,
                                              tooltip: AppLocalizations.of(
                                                context,
                                              )!
                                                  .tgCh,
                                              onPressed: () {
                                                Navigator.pop(context);
                                                launchUrl(
                                                  Uri.parse(
                                                    'https://t.me/soundal_official',
                                                  ),
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              },
                                            ),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!
                                                  .tgCh,
                                            ),
                                          ],
                                        ),*/
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          dense: true,
                        ),*/
                        ListTile(
                          title: Text(
                            AppLocalizations.of(
                              context,
                            )!
                                .moreInfo,
                          ),
                          dense: true,
                          onTap: () {
                            Navigator.pushNamed(context, '/about');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                /*Padding(
                  padding: const EdgeInsets.fromLTRB(
                    5,
                    30,
                    5,
                    20,
                  ),
                  child: Center(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!
                          .madeBy,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),*/
              ],
            ),
          ),
        ],
      ),
    );
  }

  void switchToCustomTheme() {
    const custom = 'Custom';
    if (theme != custom) {
      currentTheme.setInitialTheme(custom);
      setState(
        () {
          theme = custom;
        },
      );
    }
  }
}

class BoxSwitchTile extends StatelessWidget {
  const BoxSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.keyName,
    required this.defaultValue,
    this.isThreeLine,
    this.onChanged,
  });

  final Text title;
  final Text? subtitle;
  final String keyName;
  final bool defaultValue;
  final bool? isThreeLine;
  final Function(bool, Box box)? onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(),
      builder: (BuildContext context, Box box, Widget? widget) {
        return SwitchListTile(
          activeColor: Theme.of(context).colorScheme.secondary,
          title: title,
          subtitle: subtitle,
          isThreeLine: isThreeLine ?? false,
          dense: true,
          value: box.get(keyName, defaultValue: defaultValue) as bool? ??
              defaultValue,
          onChanged: (val) {
            box.put(keyName, val);
            onChanged?.call(val, box);
          },
        );
      },
    );
  }
}

class SpotifyCountry {
  Future<String> changeCountry({required BuildContext context}) async {
    String region =
        Hive.box('settings').get('region', defaultValue: 'Global') as String;
    if (!ConstantCodes.localChartCodes.containsKey(region)) {
      region = 'Global';
    }

    await showModalBottomSheet(
      backgroundColor: Colors.transparent,
      context: context,
      builder: (BuildContext context) {
        const Map<String, String> codes = ConstantCodes.localChartCodes;
        final List<String> countries = codes.keys.toList();
        return BottomGradientContainer(
          borderRadius: BorderRadius.circular(
            20.0,
          ),
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              0,
              10,
              0,
              10,
            ),
            itemCount: countries.length,
            itemBuilder: (context, idx) {
              return ListTileTheme(
                selectedColor: Theme.of(context).colorScheme.secondary,
                child: ListTile(
                  title: Text(
                    countries[idx],
                  ),
                  leading: Radio(
                    value: countries[idx],
                    groupValue: region,
                    onChanged: (value) {
                      top_screen.localSongs = [];
                      region = countries[idx];
                      top_screen.localFetched = false;
                      top_screen.localFetchFinished.value = false;
                      Hive.box('settings').put('region', region);
                      Navigator.pop(context);
                    },
                  ),
                  selected: region == countries[idx],
                  onTap: () {
                    top_screen.localSongs = [];
                    region = countries[idx];
                    top_screen.localFetchFinished.value = false;
                    Hive.box('settings').put('region', region);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        );
      },
    );
    return region;
  }
}
