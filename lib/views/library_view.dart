import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/media_library.dart';
import '../services/player_controller.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';

/// Biblioteca local: canciones, artistas, álbumes y carpetas. Todo offline.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  bool _searching = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Buscar canción, artista o álbum',
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                )
              : ShaderMask(
                  shaderCallback: AppColors.brandGradient.createShader,
                  child: const Text(
                    'SoundWave',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
          actions: [
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                _query = '';
              }),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Volver a escanear',
              onPressed: library.load,
            ),
          ],
          bottom: _searching
              ? null
              : const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Canciones'),
                    Tab(text: 'Artistas'),
                    Tab(text: 'Álbumes'),
                    Tab(text: 'Carpetas'),
                  ],
                ),
        ),
        body: switch (library.status) {
          LibraryStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          LibraryStatus.noPermission => _PermissionPrompt(
            onRetry: library.load,
          ),
          LibraryStatus.ready when library.songs.isEmpty =>
            const _EmptyLibrary(),
          LibraryStatus.ready =>
            _searching
                ? SongList(songs: library.search(_query))
                : TabBarView(
                    children: [
                      SongList(songs: library.songs, showShuffleHeader: true),
                      GroupList(groups: library.artists, icon: Icons.person),
                      GroupList(
                        groups: library.albums,
                        icon: Icons.album,
                        showArt: true,
                      ),
                      GroupList(groups: library.folders, icon: Icons.folder),
                    ],
                  ),
        },
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRetry;

  const _PermissionPrompt({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Para mostrar tu música, SoundWave necesita permiso para leer los audios del teléfono.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Dar permiso')),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No encontramos canciones en el teléfono ni en la tarjeta SD.\n\n'
          'Copiá tus MP3 a la carpeta Música y tocá el botón de actualizar.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Lista de canciones con un encabezado opcional de "Aleatorio".
class SongList extends StatelessWidget {
  final List<Song> songs;
  final bool showShuffleHeader;

  const SongList({
    super.key,
    required this.songs,
    this.showShuffleHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const Center(
        child: Text(
          'Sin resultados',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final header = showShuffleHeader ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: songs.length + header,
      itemBuilder: (context, i) {
        if (i < header) return PlayAllHeader(songs: songs);
        final index = i - header;
        return SongTile(song: songs[index], queue: songs, index: index);
      },
    );
  }
}

/// Botones "Reproducir" y "Aleatorio" arriba de una lista.
class PlayAllHeader extends StatelessWidget {
  final List<Song> songs;

  const PlayAllHeader({super.key, required this.songs});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            '${songs.length} canciones',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.shuffle, size: 18),
            label: const Text('Aleatorio'),
            onPressed: () => player.shuffleAll(songs),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Reproducir'),
            onPressed: () => player.playSongs(songs, 0),
          ),
        ],
      ),
    );
  }
}

class GroupList extends StatelessWidget {
  final List<SongGroup> groups;
  final IconData icon;
  final bool showArt;

  const GroupList({
    super.key,
    required this.groups,
    required this.icon,
    this.showArt = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return ListTile(
          leading: showArt
              ? SongArtwork(songId: g.songs.first.id)
              : CircleAvatar(
                  backgroundColor: AppColors.surfaceHigh,
                  child: Icon(icon, color: AppColors.accent),
                ),
          title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            g.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SongCollectionView(title: g.title, songs: g.songs),
            ),
          ),
        );
      },
    );
  }
}

/// Detalle de un artista, álbum o carpeta.
class SongCollectionView extends StatelessWidget {
  final String title;
  final List<Song> songs;

  const SongCollectionView({
    super.key,
    required this.title,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Agregar todo a una playlist',
            onPressed: () => showAddToPlaylist(context, songs),
          ),
        ],
      ),
      body: SongList(songs: songs, showShuffleHeader: true),
    );
  }
}
