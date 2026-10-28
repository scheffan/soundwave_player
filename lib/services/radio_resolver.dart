import 'package:http/http.dart' as http;

/// Muchas radios publican un archivo .pls o .m3u en vez del stream directo.
/// El reproductor no los entiende, así que los abrimos y sacamos el primer link.
class RadioResolver {
  static const _timeout = Duration(seconds: 8);

  static Future<String> resolve(String url) async {
    final lower = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final looksLikePlaylist =
        lower.endsWith('.pls') ||
        lower.endsWith('.m3u') ||
        lower.endsWith('.asx');
    if (!looksLikePlaylist) return url;

    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) return url;
      return extractStream(response.body) ?? url;
    } catch (_) {
      return url;
    }
  }

  /// Devuelve el primer link http(s) de un .pls, .m3u o .asx.
  static String? extractStream(String body) {
    for (final raw in body.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(line);
      if (match != null) return match.group(0);
    }
    return null;
  }
}
