import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/media_library.dart';
import '../services/player_controller.dart';
import '../services/radio_sources.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/mini_player.dart';
import 'equalizer_view.dart';

/// Pantalla completa de "Reproduciendo".
class NowPlayingView extends StatelessWidget {
  const NowPlayingView({super.key});

  static Route<void> route() => PageRouteBuilder(
    pageBuilder: (_, _, _) => const NowPlayingView(),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(anim),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final song = player.currentSong;
    final radio = player.currentRadio;
    if (song == null && radio == null) {
      return const Scaffold(body: Center(child: Text('Nada reproduciendo')));
    }
    final screen = MediaQuery.sizeOf(context);
    // En pantallas bajas achicamos la tapa para que entren todos los controles.
    final artSize = min(
      (screen.width - 64).clamp(160.0, 420.0),
      screen.height * 0.38,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A1B4D), AppColors.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.7],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 32,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        radio != null ? 'RADIO EN VIVO' : 'REPRODUCIENDO',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          letterSpacing: 2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.equalizer_rounded),
                      tooltip: 'Ecualizador',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EqualizerView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Hero(
                  tag: 'now-playing-art',
                  child: Container(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(color: Colors.black54, blurRadius: 30),
                      ],
                    ),
                    child: song != null
                        ? SongArtwork(
                            songId: song.id,
                            size: artSize,
                            radius: 18,
                            quality: 800,
                          )
                        : RadioLogo(url: radio!.favicon, size: artSize),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song?.title ?? radio!.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song != null
                                ? '${song.artist} · ${song.album}'
                                : radio!.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _FavoriteButton(),
                  ],
                ),
                const SizedBox(height: 16),
                if (song != null)
                  _SeekBar(player: player.player)
                else
                  const _LiveBadge(),
                const SizedBox(height: 8),
                _Controls(isRadio: radio != null),
                const SizedBox(height: 8),
                const _VolumeBar(),
                const SizedBox(height: 4),
                _BottomActions(isRadio: radio != null),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final song = player.currentSong;
    if (song != null) {
      final library = context.watch<MediaLibrary>();
      final fav = library.isFavorite(song);
      return IconButton(
        iconSize: 28,
        icon: Icon(
          fav ? Icons.favorite : Icons.favorite_border,
          color: fav ? Colors.pinkAccent : null,
        ),
        onPressed: () => library.toggleFavorite(song),
      );
    }
    final radio = player.currentRadio!;
    final repo = context.watch<RadioRepository>();
    final saved = repo.radios.where((r) => r.url == radio.url).firstOrNull;
    final fav = saved?.isFavorite ?? false;
    return IconButton(
      iconSize: 28,
      icon: Icon(
        fav ? Icons.favorite : Icons.favorite_border,
        color: fav ? Colors.pinkAccent : null,
      ),
      onPressed: () async {
        if (saved == null) {
          radio.isFavorite = true;
          await repo.add(radio);
        } else {
          await repo.toggleFavorite(saved);
        }
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '● EN VIVO',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  final AudioPlayer player;

  const _SeekBar({required this.player});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snap) {
        final total = widget.player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final value = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(
          0.0,
          max > 0 ? max : 1.0,
        );
        return Column(
          children: [
            Slider(
              value: value,
              max: max > 0 ? max : 1.0,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                widget.player.seek(Duration(milliseconds: v.round()));
                setState(() => _dragValue = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(Duration(milliseconds: value.round())),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    formatDuration(total),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Volumen multimedia del teléfono. Se mueve solo si usás los botones físicos.
class _VolumeBar extends StatefulWidget {
  const _VolumeBar();

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  final Stream<double> _volume = MediaLibrary.systemVolume;
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: _volume,
      builder: (context, snap) {
        final volume = _dragging ?? snap.data ?? 0.5;
        return Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.volume_mute_rounded,
                color: AppColors.textMuted,
              ),
              tooltip: 'Bajar volumen',
              onPressed: () => MediaLibrary.setSystemVolume(volume - 0.1),
            ),
            Expanded(
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                onChanged: (v) {
                  setState(() => _dragging = v);
                  MediaLibrary.setSystemVolume(v);
                },
                onChangeEnd: (_) => setState(() => _dragging = null),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.volume_up_rounded,
                color: AppColors.textMuted,
              ),
              tooltip: 'Subir volumen',
              onPressed: () => MediaLibrary.setSystemVolume(volume + 0.1),
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  final bool isRadio;

  const _Controls({required this.isRadio});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    if (isRadio) {
      return Center(
        child: PlayPauseButton(player: player.player, size: 36, filled: true),
      );
    }
    final loop = player.loopMode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle_rounded,
            color: player.shuffle ? AppColors.accent : AppColors.textMuted,
          ),
          tooltip: 'Aleatorio',
          onPressed: player.toggleShuffle,
        ),
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: player.previous,
        ),
        PlayPauseButton(player: player.player, size: 36, filled: true),
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: player.next,
        ),
        IconButton(
          icon: Icon(
            loop == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: loop == LoopMode.off
                ? AppColors.textMuted
                : AppColors.accent,
          ),
          tooltip: 'Repetir',
          onPressed: player.cycleLoopMode,
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  final bool isRadio;

  const _BottomActions({required this.isRadio});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        ValueListenableBuilder<Duration?>(
          valueListenable: player.sleepRemaining,
          builder: (context, left, _) => TextButton.icon(
            icon: Icon(
              Icons.bedtime_outlined,
              color: left != null ? AppColors.accent : AppColors.textMuted,
            ),
            label: Text(
              left != null ? formatDuration(left) : 'Temporizador',
              style: TextStyle(
                color: left != null ? AppColors.accent : AppColors.textMuted,
              ),
            ),
            onPressed: () => _showSleepTimer(context),
          ),
        ),
        if (!isRadio)
          TextButton.icon(
            icon: const Icon(
              Icons.queue_music_rounded,
              color: AppColors.textMuted,
            ),
            label: const Text(
              'Cola',
              style: TextStyle(color: AppColors.textMuted),
            ),
            onPressed: () => _showQueue(context),
          ),
      ],
    );
  }

  void _showSleepTimer(BuildContext context) {
    final player = context.read<PlayerController>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Apagar la música en…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final minutes in [5, 15, 30, 45, 60, 90])
              ListTile(
                title: Text('$minutes minutos'),
                onTap: () {
                  player.setSleepTimer(Duration(minutes: minutes));
                  Navigator.pop(context);
                },
              ),
            if (player.sleepRemaining.value != null)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancelar temporizador'),
                onTap: () {
                  player.setSleepTimer(null);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) {
          final player = context.watch<PlayerController>();
          final queue = player.queue;
          final order = player.player.effectiveIndices;
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Cola de reproducción',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: order.length,
                  itemBuilder: (context, i) {
                    final index = order[i];
                    if (index >= queue.length) return const SizedBox.shrink();
                    final song = queue[index];
                    final current = index == player.currentIndex;
                    return ListTile(
                      leading: SongArtwork(songId: song.id, size: 40),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: current ? AppColors.accent : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(song.artist, maxLines: 1),
                      trailing: current
                          ? const Icon(
                              Icons.graphic_eq,
                              color: AppColors.accent,
                            )
                          : IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => player.removeFromQueue(index),
                            ),
                      onTap: () => player.jumpTo(index),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
