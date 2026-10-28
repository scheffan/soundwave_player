import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import 'database_service.dart';

enum LibraryStatus { loading, noPermission, ready }

/// Una agrupación de canciones: un artista, un álbum o una carpeta.
class SongGroup {
  final String title;
  final String subtitle;
  final List<Song> songs;

  SongGroup(this.title, this.subtitle, this.songs);
}

/// Biblioteca de música local. Lee el MediaStore de Android a través del canal
/// nativo de MainActivity, así que funciona sin internet y con la microSD.
class MediaLibrary extends ChangeNotifier {
  static const _channel = MethodChannel('soundwave/media');

  final DatabaseService _db = DatabaseService.instance;

  LibraryStatus status = LibraryStatus.loading;
  List<Song> songs = [];
  Map<int, Song> _byId = {};
  Set<int> favoriteIds = {};
  List<Playlist> playlists = [];

  List<SongGroup> artists = [];
  List<SongGroup> albums = [];
  List<SongGroup> folders = [];

  // Solicitar permisos de audio compatibles con todas las versiones de Android
  Future<bool> requestPermission() async {
    // Android 13+ usa "audio"; las versiones anteriores, "storage".
    if (await Permission.audio.isGranted ||
        await Permission.storage.isGranted) {
      return true;
    }
    if ((await Permission.audio.request()).isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  Future<void> load() async {
    status = LibraryStatus.loading;
    notifyListeners();

    // Pedimos el permiso de notificaciones para mostrar los controles de reproducción.
    // Si lo rechazan, la música igual suena.
    Permission.notification.request().ignore();

    if (!await requestPermission()) {
      status = LibraryStatus.noPermission;
      notifyListeners();
      return;
    }

    final raw =
        await _channel.invokeListMethod<Map<dynamic, dynamic>>('querySongs', {
          'minDurationMs': 10000,
        }) ??
        [];
    songs = raw.map(Song.fromMap).toList();
    _byId = {for (final s in songs) s.id: s};
    _buildGroups();
    favoriteIds = await _db.getFavoriteSongIds();
    playlists = await _db.getPlaylists();
    status = LibraryStatus.ready;
    notifyListeners();
  }

  void _buildGroups() {
    Map<String, List<Song>> groupBy(String Function(Song) key) {
      final map = SplayTreeMap<String, List<Song>>(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
      for (final s in songs) {
        map.putIfAbsent(key(s), () => []).add(s);
      }
      return map;
    }

    String count(int n) => n == 1 ? '1 canción' : '$n canciones';

    artists = groupBy((s) => s.artist).entries
        .map((e) => SongGroup(e.key, count(e.value.length), e.value))
        .toList();

    albums = groupBy((s) => '${s.album}\u0000${s.albumId}').entries.map((e) {
      final list = [...e.value]..sort((a, b) => a.track.compareTo(b.track));
      return SongGroup(
        list.first.album,
        '${list.first.artist} · ${count(list.length)}',
        list,
      );
    }).toList();

    folders = groupBy((s) => s.folder).entries.map((e) {
      final name = e.key.split('/').last;
      final where = e.value.first.isOnSdCard ? 'Tarjeta SD' : 'Memoria interna';
      return SongGroup(name, '$where · ${count(e.value.length)}', e.value);
    }).toList();
  }

  Song? songById(int id) => _byId[id];

  List<Song> songsByIds(Iterable<int> ids) =>
      ids.map((id) => _byId[id]).whereType<Song>().toList();

  List<Song> get favorites => songsByIds(favoriteIds);

  List<Song> get recentlyAdded {
    final list = [...songs]..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return list.take(50).toList();
  }

  List<Song> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return songs;
    return songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q) ||
              s.album.toLowerCase().contains(q),
        )
        .toList();
  }

  bool isFavorite(Song song) => favoriteIds.contains(song.id);

  Future<void> toggleFavorite(Song song) async {
    final fav = !isFavorite(song);
    fav ? favoriteIds.add(song.id) : favoriteIds.remove(song.id);
    notifyListeners();
    await _db.setSongFavorite(song.id, fav);
  }

  // ---------- Playlists ----------

  Future<void> _reloadPlaylists() async {
    playlists = await _db.getPlaylists();
    notifyListeners();
  }

  Future<int> createPlaylist(String name) async {
    final id = await _db.createPlaylist(name);
    await _reloadPlaylists();
    return id;
  }

  Future<void> renamePlaylist(Playlist p, String name) async {
    await _db.renamePlaylist(p.id, name);
    await _reloadPlaylists();
  }

  Future<void> deletePlaylist(Playlist p) async {
    await _db.deletePlaylist(p.id);
    await _reloadPlaylists();
  }

  Future<void> addToPlaylist(int playlistId, List<Song> songs) async {
    await _db.addSongsToPlaylist(playlistId, songs.map((s) => s.id).toList());
    await _reloadPlaylists();
  }

  Future<void> removeFromPlaylist(Playlist p, Song song) async {
    await _db.removeSongFromPlaylist(p.id, song.id);
    await _reloadPlaylists();
  }

  // ---------- Carátulas ----------

  // Caché en memoria de las tapas ya leídas, para que el scroll sea fluido.
  final _artCache = _LruCache<String, Uint8List?>(300);
  final Map<String, Future<Uint8List?>> _pending = {};

  Future<Uint8List?> artwork(int songId, {int size = 200}) {
    final key = '$songId@$size';
    if (_artCache.containsKey(key)) return Future.value(_artCache[key]);
    return _pending.putIfAbsent(key, () async {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('artwork', {
          'id': songId,
          'size': size,
        });
        _artCache[key] = bytes;
        return bytes;
      } catch (_) {
        _artCache[key] = null;
        return null;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Uint8List? cachedArtwork(int songId, {int size = 200}) =>
      _artCache['$songId@$size'];

  /// Abre la app de radio FM de fábrica, si el teléfono tiene una.
  static Future<bool> openFmRadio() async =>
      await _channel.invokeMethod<bool>('openFmRadio') ?? false;
}

class _LruCache<K, V> {
  final int capacity;
  final _map = <K, V>{};

  _LruCache(this.capacity);

  bool containsKey(K key) => _map.containsKey(key);

  V? operator [](K key) {
    if (!_map.containsKey(key)) return null;
    final value = _map.remove(key) as V;
    _map[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first);
  }
}
