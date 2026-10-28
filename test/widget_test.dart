import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soundwave_player/models/song.dart';
import 'package:soundwave_player/services/radio_resolver.dart';
import 'package:soundwave_player/services/radio_sources.dart';
import 'package:soundwave_player/theme.dart';

void main() {
  group('Song', () {
    test('usa el nombre del archivo si no hay título y detecta la microSD', () {
      final song = Song.fromMap({
        'id': 7,
        'title': '',
        'artist': '<unknown>',
        'album': null,
        'albumId': 3,
        'durationMs': 185000,
        'path': '/storage/1A2B-3C4D/Music/Rock/tema_uno.mp3',
        'uri': 'content://media/external/audio/media/7',
        'track': 1,
        'dateAdded': 1700000000,
      });
      expect(song.title, 'tema_uno');
      expect(song.artist, 'Artista desconocido');
      expect(song.album, 'Álbum desconocido');
      expect(song.isOnSdCard, isTrue);
      expect(song.folder, '/storage/1A2B-3C4D/Music/Rock');
      expect(song.duration, const Duration(minutes: 3, seconds: 5));
    });

    test('la memoria interna no cuenta como SD', () {
      final song = Song.fromMap({
        'id': 1,
        'title': 'x',
        'path': '/storage/emulated/0/Music/x.mp3',
        'uri': 'content://x',
      });
      expect(song.isOnSdCard, isFalse);
    });
  });

  test('extrae el stream de un .pls y de un .m3u', () {
    const pls =
        '[playlist]\nNumberOfEntries=1\nFile1=http://stream.example.com:8000/live\nTitle1=Radio';
    const m3u = '#EXTM3U\n#EXTINF:-1,Radio\nhttps://example.com/radio.mp3\n';
    expect(
      RadioResolver.extractStream(pls),
      'http://stream.example.com:8000/live',
    );
    expect(RadioResolver.extractStream(m3u), 'https://example.com/radio.mp3');
  });

  group('FlavibotImporter.parse', () {
    test('lee el payload de Nuxt', () {
      final payload = jsonEncode([
        {'data': 1},
        [2, 5],
        {'name': 3, 'url': 4},
        'NRJ',
        'https://scdn.nrjaudio.fm/adwz2/fr/30001/mp3_128.mp3',
        {'name': 6, 'url': 7},
        'RMF FM',
        'http://217.74.72.11/rmf_fm',
      ]);
      final html =
          '<html><body><script type="application/json" id="__NUXT_DATA__" '
          'data-ssr="true">$payload</script></body></html>';
      final radios = FlavibotImporter.parse(html);
      expect(radios.map((r) => r.name), ['NRJ', 'RMF FM']);
      expect(radios.last.url, 'http://217.74.72.11/rmf_fm');
      expect(radios.every((r) => r.source == 'flavibot'), isTrue);
    });

    test('lee botones de copiar con el link en un atributo', () {
      const html =
          '<div><span class="name">Skyrock National</span>'
          '<button data-clipboard-text="https://icecast.skyrock.net/s/natio_mp3_128k">Copy link</button></div>'
          '<a href="https://flavibot.xyz/premium" data-url="https://flavibot.xyz/x">x</a>';
      final radios = FlavibotImporter.parse(html);
      expect(radios, hasLength(1));
      expect(radios.single.name, 'Skyrock National');
    });
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
