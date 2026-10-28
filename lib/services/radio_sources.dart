import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/radio_station.dart';
import 'database_service.dart';

/// Lista de radios guardadas en el teléfono, con favoritas y recientes.
class RadioRepository extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  List<RadioStation> radios = [];
  bool loaded = false;

  List<RadioStation> get favorites =>
      radios.where((r) => r.isFavorite).toList();

  List<RadioStation> get recent {
    final list = radios.where((r) => r.lastPlayed != null).toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
    return list.take(10).toList();
  }

  Future<void> load() async {
    radios = await _db.getRadioStations();
    if (radios.isEmpty) {
      // Primera vez que se abre la app: cargamos las radios que vienen incluidas.
      await _db.addRadios(await bundledRadios());
      radios = await _db.getRadioStations();
    }
    loaded = true;
    notifyListeners();
  }

  /// Radios incluidas en el APK (assets/radios.json), disponibles sin internet.
  static Future<List<RadioStation>> bundledRadios() async {
    try {
      final raw = await rootBundle.loadString('assets/radios.json');
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return RadioStation(
          name: m['name'] as String,
          url: m['url'] as String,
          genre: m['genre'] as String?,
          country: m['country'] as String?,
          favicon: m['favicon'] as String?,
          source: m['source'] as String? ?? 'flavibot',
        );
      }).toList();
    } catch (e) {
      debugPrint('No se pudieron leer las radios incluidas: $e');
      return [];
    }
  }

  Future<void> add(RadioStation radio) async {
    await _db.addRadio(radio);
    await load();
  }

  Future<int> addAll(List<RadioStation> list) async {
    final added = await _db.addRadios(list);
    await load();
    return added;
  }

  Future<void> update(RadioStation radio) async {
    await _db.updateRadio(radio);
    await load();
  }

  Future<void> delete(RadioStation radio) async {
    if (radio.id == null) return;
    await _db.deleteRadio(radio.id!);
    await load();
  }

  Future<void> toggleFavorite(RadioStation radio) async {
    if (radio.id == null) return;
    await _db.toggleFavorite(radio.id!, radio.isFavorite);
    await load();
  }

  bool contains(String url) => radios.any((r) => r.url == url);

  Future<void> markPlayed(RadioStation radio) async {
    radio.lastPlayed = DateTime.now();
    notifyListeners();
  }
}

/// Cliente de Radio Browser (radio-browser.info), una base pública y gratuita
/// con decenas de miles de radios de todo el mundo.
class RadioBrowserApi {
  static const _servers = [
    'de1.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
    'de2.api.radio-browser.info',
  ];
  static final _random = Random();

  static Future<List<RadioStation>> search({
    String name = '',
    String? countryCode,
    String? tag,
    int limit = 60,
  }) async {
    final params = {
      'limit': '$limit',
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      if (name.isNotEmpty) 'name': name,
      'countrycode': ?countryCode,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
    };
    final servers = [..._servers]..shuffle(_random);
    Object? lastError;
    for (final host in servers) {
      try {
        final uri = Uri.https(host, '/json/stations/search', params);
        final response = await http
            .get(uri, headers: {'User-Agent': 'SoundWavePlayer/1.0'})
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;
        final list =
            jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return list.map((e) {
          final m = e as Map<String, dynamic>;
          final tags = (m['tags'] as String? ?? '')
              .split(',')
              .where((t) => t.isNotEmpty)
              .take(2)
              .join(', ');
          final url = (m['url_resolved'] as String?)?.isNotEmpty == true
              ? m['url_resolved'] as String
              : m['url'] as String;
          return RadioStation(
            name: (m['name'] as String).trim(),
            url: url,
            genre: tags.isEmpty ? null : tags,
            country: m['country'] as String?,
            favicon: (m['favicon'] as String?)?.isEmpty == true
                ? null
                : m['favicon'] as String?,
            source: 'radio-browser',
          );
        }).toList();
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Sin conexión con Radio Browser: $lastError');
  }
}

/// Importa la lista pública de https://flavibot.xyz/radios descargando la página.
/// Cada radio de la web tiene un botón que copia su link; acá leemos esos links
/// directamente del HTML.
class FlavibotImporter {
  static const baseUrl = 'https://flavibot.xyz/radios';

  static Future<List<RadioStation>> fetchAll({int maxPages = 20}) async {
    final result = <String, RadioStation>{};
    for (var page = 1; page <= maxPages; page++) {
      final uri = Uri.parse(page == 1 ? baseUrl : '$baseUrl?page=$page');
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android) SoundWavePlayer/1.0',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) break;
      final found = parse(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      final before = result.length;
      for (final r in found) {
        result.putIfAbsent(r.url, () => r);
      }
      // Si la página no trajo radios nuevas, llegamos al final.
      if (result.length == before) break;
    }
    return result.values.toList();
  }

  /// Busca en el HTML pares de nombre y link de stream.
  @visibleForTesting
  static List<RadioStation> parse(String html) {
    final stations = <RadioStation>[];
    final seen = <String>{};

    // 0) flavibot está hecho con Nuxt: los datos de la página viajan en el script
    //    __NUXT_DATA__, un arreglo donde los objetos guardan índices a sus valores.
    final nuxt = RegExp(
      r'<script[^>]*id="__NUXT_DATA__"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (nuxt != null) {
      try {
        final data = jsonDecode(nuxt.group(1)!) as List<dynamic>;
        dynamic value(dynamic ref) =>
            ref is int && ref >= 0 && ref < data.length ? data[ref] : null;
        for (final item in data) {
          if (item is! Map) continue;
          final name = value(item['name']) ?? value(item['title']);
          final url =
              value(item['url']) ??
              value(item['stream']) ??
              value(item['streamUrl']) ??
              value(item['stream_url']) ??
              value(item['link']);
          if (name is String && url is String && url.startsWith('http')) {
            _add(stations, seen, name, url);
          }
        }
      } catch (e) {
        debugPrint('No se pudo leer __NUXT_DATA__: $e');
      }
    }

    // 1) Datos embebidos como JSON (Next.js, Nuxt, etc.): objetos con name y url.
    final jsonLike = RegExp(
      r'''\{[^{}]*?"name"\s*:\s*"((?:[^"\\]|\\.)*)"[^{}]*?"(?:url|stream|link|streamUrl|stream_url)"\s*:\s*"(https?:(?:[^"\\]|\\.)*)"[^{}]*\}''',
    );
    for (final m in jsonLike.allMatches(html)) {
      _add(stations, seen, _unescape(m.group(1)!), _unescape(m.group(2)!));
    }

    // 2) Botones "Copiar link" con el link en un atributo (data-url, data-clipboard-text...).
    final attr = RegExp(
      r'''data-(?:url|link|stream|clipboard-text|copy)\s*=\s*["'](https?://[^"']+)["']''',
      caseSensitive: false,
    );
    for (final m in attr.allMatches(html)) {
      final url = _unescape(m.group(1)!);
      final name = _nameBefore(html, m.start);
      _add(stations, seen, name ?? Uri.parse(url).host, url);
    }

    return stations;
  }

  static void _add(
    List<RadioStation> list,
    Set<String> seen,
    String name,
    String url,
  ) {
    final clean = url.trim();
    final host = Uri.tryParse(clean)?.host ?? '';
    if (host.isEmpty || host.contains('flavibot')) return;
    if (!seen.add(clean)) return;
    list.add(
      RadioStation(
        name: name.trim().isEmpty ? host : name.trim(),
        url: clean,
        source: 'flavibot',
      ),
    );
  }

  // El nombre suele ser el último texto visible antes del botón de copiar.
  static String? _nameBefore(String html, int index) {
    final start = max(0, index - 600);
    final chunk = html.substring(start, index);
    final texts = RegExp(r'>([^<>]{2,80})<')
        .allMatches(chunk)
        .map((m) => m.group(1)!.trim())
        .where((t) => t.isNotEmpty && !t.toLowerCase().contains('copy'))
        .toList();
    return texts.isEmpty ? null : _unescape(texts.last);
  }

  static String _unescape(String s) => s
      .replaceAll(r'\/', '/')
      .replaceAll(r'&', '&')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"');
}
