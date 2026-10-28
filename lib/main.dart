import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'services/media_library.dart';
import 'services/player_controller.dart';
import 'services/radio_sources.dart';
import 'theme.dart';
import 'views/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Controles en la notificación y la pantalla de bloqueo, y música con la pantalla apagada.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.soundwave.soundwave_player.playback',
    androidNotificationChannelName: 'Reproducción',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_stat_music',
  );

  final library = MediaLibrary();
  final radios = RadioRepository();
  final player = PlayerController(library);
  await player.init();

  // La biblioteca y las radios se cargan en segundo plano; la pantalla aparece enseguida.
  library.load().whenComplete(player.restore);
  radios.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: radios),
        ChangeNotifierProvider.value(value: player),
      ],
      child: const SoundWaveApp(),
    ),
  );
}

class SoundWaveApp extends StatelessWidget {
  const SoundWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoundWave Player',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeView(),
    );
  }
}
