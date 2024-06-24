import 'dart:async';
import 'dart:isolate';

import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:soundal/Helpers/logging.dart';
import 'package:soundal/Screens/Player/audioplayer.dart';
import 'package:soundal/Services/youtube_services.dart';

SendPort? refreshIsolateSendPort;

Future<void> startBackgroundProcessing() async {
  final AudioPlayerHandler audioHandler = GetIt.I<AudioPlayerHandler>();
  final refreshIsolateReceivePort = ReceivePort();
  await Isolate.spawn(
    _refreshIsolateBackgroundProcess,
    refreshIsolateReceivePort.sendPort,
  );

  refreshIsolateReceivePort.listen((message) async {
    if (refreshIsolateSendPort == null) {
      Logger.root.info('setting refreshIsolateSendPort');
      refreshIsolateSendPort = message as SendPort;
      final appDocumentDirectoryPath =
          (await getApplicationDocumentsDirectory()).path;
      refreshIsolateSendPort?.send(appDocumentDirectoryPath);
    } else {
      await audioHandler.customAction('refreshLink', {'newData': message});
    }
  });
}

// The function that will run in the background Isolate
Future<void> _refreshIsolateBackgroundProcess(SendPort sendPort) async {
  final isolateReceivePort = ReceivePort();
  sendPort.send(isolateReceivePort.sendPort);
  bool hiveInit = false;

  await for (final message in isolateReceivePort) {
    if (!hiveInit) {
      Hive.init(message.toString());
      await Hive.openBox('ytlinkcache');
      await Hive.openBox('settings');
      hiveInit = true;
      continue;
    }
    final newData = await YouTubeServices().refreshLink(message.toString());
    sendPort.send(newData);
  }
}

void addIdToRefreshIsolateProcessing(String id) {
  refreshIsolateSendPort?.send(id);
}
