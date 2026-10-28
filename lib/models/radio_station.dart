class RadioStation {
  final int? id;
  final String name;
  final String url;
  final String? genre;
  final String? country;
  final String? favicon;

  /// De dónde salió la radio: 'manual', 'flavibot' o 'radio-browser'.
  final String source;
  bool isFavorite;
  DateTime? lastPlayed;

  RadioStation({
    this.id,
    required this.name,
    required this.url,
    this.genre,
    this.country,
    this.favicon,
    this.source = 'manual',
    this.isFavorite = false,
    this.lastPlayed,
  });

  // Convertir a Map para guardar en la base de datos local (SQLite)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'genre': genre,
      'country': country,
      'favicon': favicon,
      'source': source,
      'isFavorite': isFavorite ? 1 : 0,
      'lastPlayed': lastPlayed?.millisecondsSinceEpoch,
    };
  }

  // Crear una estación a partir de lo que devuelve la base de datos
  factory RadioStation.fromMap(Map<String, dynamic> map) {
    final lastPlayed = map['lastPlayed'] as int?;
    return RadioStation(
      id: map['id'],
      name: map['name'],
      url: map['url'],
      genre: map['genre'],
      country: map['country'],
      favicon: map['favicon'],
      source: map['source'] ?? 'manual',
      isFavorite: map['isFavorite'] == 1,
      lastPlayed: lastPlayed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastPlayed),
    );
  }

  /// Línea secundaria que se muestra debajo del nombre.
  String get subtitle {
    final parts = [
      genre,
      country,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? 'Radio online' : parts.join(' · ');
  }
}
