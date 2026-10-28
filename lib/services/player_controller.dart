import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/radio_station.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'media_library.dart';
import 'radio_resolver.dart';

/// Reproductor único de la app. Maneja la cola de canciones locales, las radios,
/// el temporizador de apagado y recuerda dónde quedaste al cerrar la app.
class PlayerController extends ChangeNotifier {
  PlayerController(this._library) {
    player = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );
  }

  final MediaLibrary _library;
  final _random = Random();
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer player;

  List<Song> _queue = [];
  RadioStation? _radio;
  SharedPreferences? _prefs;
  Timer? _saveTimer;
  Timer? _sleepTimer;
  bool _restored = false;

  /// Tiempo que falta para que se apague la música, o null si no hay temporizador.
  final ValueNotifier<Duration?> sleepRemaining = ValueNotifier(null);

  /// Mensajes cortos para mostrar al usuario (errores de conexión, etc.).
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  List<Song> get queue => List.unmodifiable(_queue);
  RadioStation? get currentRadio => _radio;
  bool get isRadio => _radio != null;
  int? get currentIndex => player.currentIndex;

  Song? get currentSong {
    if (_radio != null) return null;
    final i = player.currentIndex;
    if (i == null || i < 0 || i >= _queue.length) return null;
    return _queue[i];
  }

  bool get hasMedia => _radio != null || currentSong != null;
  bool get shuffle => player.shuffleModeEnabled;
  LoopMode get loopMode => player.loopMode;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _prefs = await SharedPreferences.getInstance();

    player.currentIndexStream.listen((_) {
      notifyListeners();
      _saveState();
    });
    player.playingStream.listen((playing) {
      if (!playing) _saveState();
    });
    player.errorStream.listen((e) {
      _messages.add(
        isRadio
            ? 'No se pudo conectar con la radio. Revisá tu conexión o probá otra.'
            : 'No se pudo reproducir este archivo.',
      );
    });

    // Guardamos la posición cada 10 segundos mientras suena.
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (player.playing) _saveState();
    });

    await _restoreEqualizer();
  }

  // ---------- Canciones locales ----------

  MediaItem _mediaItem(Song s) => MediaItem(
    id: 'song:${s.id}',
    title: s.title,
    artist: s.artist,
    album: s.album,
    duration: s.duration,
    artUri: s.albumArtUri,
  );

  AudioSource _source(Song s) =>
      AudioSource.uri(Uri.parse(s.uri), tag: _mediaItem(s));

  /// Reproduce una lista de canciones empezando por [index].
  Future<void> playSongs(
    List<Song> songs,
    int index, {
    bool shuffle = false,
  }) async {
    if (songs.isEmpty) return;
    _radio = null;
    _queue = [...songs];
    try {
      // En aleatorio arrancamos por una canción al azar; el resto se mezcla después de ella.
      final start = shuffle ? _random.nextInt(_queue.length) : index;
      await player.setShuffleModeEnabled(shuffle);
      await player.setAudioSources(
        _queue.map(_source).toList(),
        initialIndex: start,
      );
      if (shuffle) await player.shuffle();
      notifyListeners();
      await player.play();
    } catch (e) {
      debugPrint('Error al reproducir archivo local: $e');
    }
  }

  Future<void> shuffleAll(List<Song> songs) =>
      playSongs(songs, 0, shuffle: true);

  /// Agrega canciones para que suenen después de la actual.
  Future<void> playNext(List<Song> songs) async {
    if (isRadio || _queue.isEmpty) return playSongs(songs, 0);
    final at = (player.currentIndex ?? -1) + 1;
    _queue.insertAll(at, songs);
    await player.insertAudioSources(at, songs.map(_source).toList());
    notifyListeners();
  }

  /// Agrega canciones al final de la cola.
  Future<void> addToQueue(List<Song> songs) async {
    if (isRadio || _queue.isEmpty) return playSongs(songs, 0);
    _queue.addAll(songs);
    await player.addAudioSources(songs.map(_source).toList());
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    await player.removeAudioSourceAt(index);
    notifyListeners();
  }

  Future<void> jumpTo(int index) async {
    await player.seek(Duration.zero, index: index);
    if (!player.playing) await player.play();
  }

  // ---------- Radios ----------

  Future<void> playRadio(RadioStation radio) async {
    _radio = radio;
    _queue = [];
    notifyListeners();
    try {
      await player.stop();
      final url = await RadioResolver.resolve(radio.url);
      await player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: 'radio:${radio.url}',
            title: radio.name,
            artist: radio.subtitle,
            artUri: radio.favicon != null && radio.favicon!.startsWith('http')
                ? Uri.tryParse(radio.favicon!)
                : null,
            extras: {'isLive': true},
          ),
        ),
      );
      if (radio.id != null) {
        DatabaseService.instance.markRadioPlayed(radio.id!).ignore();
      }
      await player.play();
    } catch (e) {
      debugPrint('Error al reproducir el stream: $e');
      _messages.add('No se pudo conectar con ${radio.name}. ¿Tenés internet?');
    }
    _saveState();
  }

  // ---------- Controles ----------

  Future<void> togglePlay() => player.playing ? player.pause() : player.play();

  Future<void> next() => player.seekToNext();

  Future<void> previous() async {
    // Como en todos los reproductores: si ya pasaron 3 segundos, vuelve al principio.
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
    notifyListeners();
    _saveState();
  }

  /// Rota entre: sin repetir, repetir todo, repetir una.
  Future<void> cycleLoopMode() async {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    final next = order[(order.indexOf(player.loopMode) + 1) % order.length];
    await player.setLoopMode(next);
    notifyListeners();
    _saveState();
  }

  // ---------- Temporizador de apagado ----------

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      sleepRemaining.value = null;
      return;
    }
    final end = DateTime.now().add(duration);
    sleepRemaining.value = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) {
        t.cancel();
        sleepRemaining.value = null;
        player.pause();
      } else {
        sleepRemaining.value = left;
      }
    });
  }

  // ---------- Ecualizador ----------

  Future<void> setEqualizerEnabled(bool enabled) async {
    await equalizer.setEnabled(enabled);
    await _prefs?.setBool('eq_enabled', enabled);
    notifyListeners();
  }

  Future<void> setBandGain(AndroidEqualizerBand band, double gain) async {
    await band.setGain(gain);
    await _prefs?.setDouble('eq_band_${band.index}', gain);
  }

  Future<void> _restoreEqualizer() async {
    final enabled = _prefs?.getBool('eq_enabled') ?? false;
    if (!enabled) return;
    await equalizer.setEnabled(true);
    // Las bandas existen recién cuando el reproductor cargó algo.
    equalizer.parameters.then((params) async {
      for (final band in params.bands) {
        final gain = _prefs?.getDouble('eq_band_${band.index}');
        if (gain != null) await band.setGain(gain);
      }
    }).ignore();
  }

  // ---------- Recordar dónde quedaste ----------

  void _saveState() {
    final prefs = _prefs;
    if (prefs == null || !_restored) return;
    if (_radio != null) {
      prefs.setString('last_radio_url', _radio!.url);
      prefs.setString('last_radio_name', _radio!.name);
      prefs.remove('queue_ids');
      return;
    }
    if (_queue.isEmpty) return;
    prefs.remove('last_radio_url');
    prefs.setStringList(
      'queue_ids',
      _queue.map((s) => s.id.toString()).toList(),
    );
    prefs.setInt('queue_index', player.currentIndex ?? 0);
    prefs.setInt('queue_position_ms', player.position.inMilliseconds);
    prefs.setBool('shuffle', player.shuffleModeEnabled);
    prefs.setInt('loop_mode', player.loopMode.index);
  }

  /// Deja cargada (en pausa) la última cola que estabas escuchando.
  Future<void> restore() async {
    if (_restored) return;
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final loop = prefs.getInt('loop_mode');
      if (loop != null) await player.setLoopMode(LoopMode.values[loop]);

      final ids = prefs.getStringList('queue_ids');
      if (ids != null && ids.isNotEmpty) {
        final songs = _library.songsByIds(ids.map(int.parse));
        if (songs.isNotEmpty) {
          final index = (prefs.getInt('queue_index') ?? 0).clamp(
            0,
            songs.length - 1,
          );
          _queue = songs;
          await player.setAudioSources(
            songs.map(_source).toList(),
            initialIndex: index,
            initialPosition: Duration(
              milliseconds: prefs.getInt('queue_position_ms') ?? 0,
            ),
          );
          await player.setShuffleModeEnabled(prefs.getBool('shuffle') ?? false);
        }
      }
    } catch (e) {
      debugPrint('No se pudo restaurar la cola: $e');
    }
    _restored = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    _messages.close();
    player.dispose();
    super.dispose();
  }
}
