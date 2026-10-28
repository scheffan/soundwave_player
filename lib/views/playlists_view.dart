import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/media_library.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';
import 'library_view.dart';

/// Playlists propias, más dos automáticas: Favoritas y Agregadas recientemente.
class PlaylistsView extends StatelessWidget {
  const PlaylistsView({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nueva playlist',
            onPressed: () async {
              final name = await askText(context, 'Nueva playlist', 'Nombre');
              if (name != null && name.isNotEmpty) {
                await library.createPlaylist(name);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _SmartTile(
            title: 'Favoritas',
            icon: Icons.favorite,
            color: Colors.pinkAccent,
            songs: library.favorites,
          ),
          _SmartTile(
            title: 'Agregadas recientemente',
            icon: Icons.schedule,
            color: AppColors.accent,
            songs: library.recentlyAdded,
          ),
          const Divider(indent: 16, endIndent: 16),
          if (library.playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Todavía no tenés playlists. Tocá + para crear una, o usá el menú ⋮ de cualquier canción.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          for (final p in library.playlists)
            ListTile(
              leading: p.songIds.isEmpty
                  ? const ArtPlaceholder(size: 48, icon: Icons.queue_music)
                  : SongArtwork(songId: p.songIds.first),
              title: Text(p.name),
              subtitle: Text('${p.songIds.length} canciones'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailView(playlistId: p.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmartTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Song> songs;

  const _SmartTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text('${songs.length} canciones'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SongCollectionView(title: title, songs: songs),
        ),
      ),
    );
  }
}

class PlaylistDetailView extends StatelessWidget {
  final int playlistId;

  const PlaylistDetailView({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    final Playlist? playlist = library.playlists
        .where((p) => p.id == playlistId)
        .firstOrNull;
    if (playlist == null) return const Scaffold();
    final songs = library.songsByIds(playlist.songIds);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name, style: const TextStyle(fontSize: 20)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'rename') {
                final name = await askText(
                  context,
                  'Renombrar',
                  'Nombre',
                  initial: playlist.name,
                );
                if (name != null && name.isNotEmpty) {
                  await library.renamePlaylist(playlist, name);
                }
              } else if (action == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('¿Borrar playlist?'),
                    content: Text(
                      'Se borra "${playlist.name}". Las canciones no se tocan.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Borrar'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await library.deletePlaylist(playlist);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renombrar')),
              PopupMenuItem(value: 'delete', child: Text('Borrar playlist')),
            ],
          ),
        ],
      ),
      body: songs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Playlist vacía. Agregá canciones desde el menú ⋮ de cada una.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          : ListView.builder(
              itemCount: songs.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return PlayAllHeader(songs: songs);
                final song = songs[i - 1];
                return SongTile(
                  song: song,
                  queue: songs,
                  index: i - 1,
                  extraActions: const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Quitar de esta playlist'),
                    ),
                  ],
                  onExtraAction: (a) {
                    if (a == 'remove') {
                      library.removeFromPlaylist(playlist, song);
                    }
                  },
                );
              },
            ),
    );
  }
}
