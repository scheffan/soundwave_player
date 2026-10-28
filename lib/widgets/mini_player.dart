import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/player_controller.dart';
import '../theme.dart';
import '../views/now_playing_view.dart';
import 'artwork.dart';

/// Barra fija abajo que muestra qué está sonando. Al tocarla abre "Reproduciendo".
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    if (!player.hasMedia) return const SizedBox.shrink();

    final song = player.currentSong;
    final radio = player.currentRadio;
    final title = song?.title ?? radio!.name;
    final subtitle = song?.artist ?? 'En vivo · ${radio!.subtitle}';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(NowPlayingView.route()),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) {
          Navigator.of(context).push(NowPlayingView.route());
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
              child: Row(
                children: [
                  Hero(
                    tag: 'now-playing-art',
                    child: song != null
                        ? SongArtwork(songId: song.id, size: 44)
                        : RadioLogo(url: radio!.favicon, size: 44),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PlayPauseButton(player: player.player, size: 30),
                  if (song != null)
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: player.next,
                    ),
                ],
              ),
            ),
            if (song != null) _ProgressLine(player: player.player),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final AudioPlayer player;

  const _ProgressLine({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final total = player.duration?.inMilliseconds ?? 0;
        final pos = snap.data?.inMilliseconds ?? 0;
        return LinearProgressIndicator(
          value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
          minHeight: 2,
          backgroundColor: Colors.white10,
          color: AppColors.accent,
        );
      },
    );
  }
}

/// Botón de play/pausa que muestra una ruedita mientras carga (útil para radios).
class PlayPauseButton extends StatelessWidget {
  final AudioPlayer player;
  final double size;
  final bool filled;

  const PlayPauseButton({
    super.key,
    required this.player,
    this.size = 32,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final processing = state?.processingState;
        final playing = state?.playing ?? false;
        final loading =
            processing == ProcessingState.loading ||
            processing == ProcessingState.buffering;

        final Widget icon = loading
            ? SizedBox(
                width: size * 0.8,
                height: size * 0.8,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: filled ? Colors.black : Colors.white,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: size,
                color: filled ? Colors.black : null,
              );

        void onPressed() => playing ? player.pause() : player.play();

        if (!filled) return IconButton(icon: icon, onPressed: onPressed);
        return Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size * 2,
              height: size * 2,
              child: Center(child: icon),
            ),
          ),
        );
      },
    );
  }
}
