import 'package:path/path.dart' as p;

class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int albumId;
  final Duration duration;
  final String path;
  final String uri;
  final int track;
  final DateTime dateAdded;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.duration,
    required this.path,
    required this.uri,
    required this.track,
    required this.dateAdded,
  });

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    final path = map['path'] as String? ?? '';
    String clean(String? value, String fallback) =>
        (value == null || value.isEmpty || value == '<unknown>')
        ? fallback
        : value;
    return Song(
      id: (map['id'] as num).toInt(),
      title: clean(map['title'] as String?, p.basenameWithoutExtension(path)),
      artist: clean(map['artist'] as String?, 'Artista desconocido'),
      album: clean(map['album'] as String?, 'Álbum desconocido'),
      albumId: (map['albumId'] as num?)?.toInt() ?? 0,
      duration: Duration(
        milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0,
      ),
      path: path,
      uri: map['uri'] as String,
      track: (map['track'] as num?)?.toInt() ?? 0,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(
        ((map['dateAdded'] as num?)?.toInt() ?? 0) * 1000,
      ),
    );
  }

  /// Carpeta donde está el archivo, por ejemplo /storage/emulated/0/Music/Rock.
  String get folder => p.dirname(path);

  /// Memoria interna o tarjeta SD, según el volumen del archivo.
  bool get isOnSdCard =>
      path.startsWith('/storage/') && !path.startsWith('/storage/emulated/');

  /// Carátula del álbum que Android expone para la notificación y la pantalla de bloqueo.
  Uri get albumArtUri =>
      Uri.parse('content://media/external/audio/albumart/$albumId');
}
