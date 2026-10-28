import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/media_library.dart';
import '../services/player_controller.dart';
import '../theme.dart';
import 'artwork.dart';

/// Fila de una canción. Al tocarla reproduce [queue] empezando por ella.
class SongTile extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  final Widget? trailingExtra;
  final List<PopupMenuEntry<String>> extraActions;
  final void Function(String action)? onExtraAction;

  const SongTile({
    super.key,
    required this.song,
    required this.queue,
    required this.index,
    this.trailingExtra,
    this.extraActions = const [],
    this.onExtraAction,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<PlayerController, bool>(
      (p) => p.currentSong?.id == song.id,
    );
    return ListTile(
      leading: SongArtwork(songId: song.id),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrent ? AppColors.accent : null,
        ),
      ),
      subtitle: Text(
        '${song.artist} · ${formatDuration(song.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            const Icon(Icons.graphic_eq, color: AppColors.accent, size: 20),
          ?trailingExtra,
          SongMenuButton(
            song: song,
            extraActions: extraActions,
            onExtraAction: onExtraAction,
          ),
        ],
      ),
      onTap: () => context.read<PlayerController>().playSongs(queue, index),
    );
  }
}

class SongMenuButton extends StatelessWidget {
  final Song song;
  final List<PopupMenuEntry<String>> extraActions;
  final void Function(String action)? onExtraAction;

  const SongMenuButton({
    super.key,
    required this.song,
    this.extraActions = const [],
    this.onExtraAction,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.read<MediaLibrary>();
    final player = context.read<PlayerController>();
    final fav = library.isFavorite(song);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
      onSelected: (action) async {
        switch (action) {
          case 'next':
            await player.playNext([song]);
            if (context.mounted) _toast(context, 'Suena a continuación');
          case 'queue':
            await player.addToQueue([song]);
            if (context.mounted) _toast(context, 'Agregada a la cola');
          case 'fav':
            await library.toggleFavorite(song);
          case 'playlist':
            if (context.mounted) await showAddToPlaylist(context, [song]);
          default:
            onExtraAction?.call(action);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'next',
          child: Text('Reproducir a continuación'),
        ),
        const PopupMenuItem(value: 'queue', child: Text('Agregar a la cola')),
        const PopupMenuItem(
          value: 'playlist',
          child: Text('Agregar a playlist…'),
        ),
        PopupMenuItem(
          value: 'fav',
          child: Text(fav ? 'Quitar de favoritas' : 'Agregar a favoritas'),
        ),
        ...extraActions,
      ],
    );
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}

/// Hoja para elegir (o crear) la playlist donde agregar canciones.
Future<void> showAddToPlaylist(BuildContext context, List<Song> songs) async {
  final library = context.read<MediaLibrary>();
  final chosen = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Agregar a playlist',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add, color: AppColors.accent),
            title: const Text('Nueva playlist'),
            onTap: () async {
              final name = await askText(context, 'Nueva playlist', 'Nombre');
              if (name == null || name.isEmpty) return;
              final id = await library.createPlaylist(name);
              if (context.mounted) Navigator.pop(context, id);
            },
          ),
          for (final p in library.playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.songIds.length} canciones'),
              onTap: () => Navigator.pop(context, p.id),
            ),
        ],
      ),
    ),
  );
  if (chosen == null) return;
  await library.addToPlaylist(chosen, songs);
  if (context.mounted) _toast(context, 'Agregada a la playlist');
}

/// Diálogo simple para escribir un texto (nombre de playlist, etc.).
Future<String?> askText(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
