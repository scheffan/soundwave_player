import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/media_library.dart';
import '../theme.dart';

/// Tapa del disco de una canción, con un degradé de la marca si no tiene.
class SongArtwork extends StatelessWidget {
  final int songId;
  final double size;
  final double radius;
  final int quality;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 48,
    this.radius = 8,
    this.quality = 200,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.read<MediaLibrary>();
    final cached = library.cachedArtwork(songId, size: quality);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: cached != null
            ? Image.memory(cached, fit: BoxFit.cover, gaplessPlayback: true)
            : FutureBuilder<Uint8List?>(
                future: library.artwork(songId, size: quality),
                builder: (context, snap) {
                  final bytes = snap.data;
                  if (bytes == null) return ArtPlaceholder(size: size);
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              ),
      ),
    );
  }
}

class ArtPlaceholder extends StatelessWidget {
  final double size;
  final IconData icon;

  const ArtPlaceholder({
    super.key,
    required this.size,
    this.icon = Icons.music_note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.55),
            AppColors.accent.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, size: size * 0.45, color: Colors.white70),
    );
  }
}

/// Logo de una radio (si la base de datos tiene uno) o un ícono de antena.
class RadioLogo extends StatelessWidget {
  final String? url;
  final double size;

  const RadioLogo({super.key, this.url, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final placeholder = ArtPlaceholder(size: size, icon: Icons.radio);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: url == null || !url!.startsWith('http')
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
