import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/player_controller.dart';
import '../theme.dart';

/// Ecualizador del sistema Android, aplicado a todo lo que suena en la app.
class EqualizerView extends StatelessWidget {
  const EqualizerView({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final eq = player.equalizer;
    return Scaffold(
      appBar: AppBar(title: const Text('Ecualizador')),
      body: StreamBuilder<bool>(
        stream: eq.enabledStream,
        builder: (context, enabledSnap) {
          final enabled = enabledSnap.data ?? false;
          return Column(
            children: [
              SwitchListTile(
                title: const Text('Activar ecualizador'),
                value: enabled,
                onChanged: player.setEqualizerEnabled,
              ),
              Expanded(
                child: FutureBuilder<AndroidEqualizerParameters>(
                  future: eq.parameters,
                  builder: (context, snap) {
                    final params = snap.data;
                    if (params == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Reproducí algo para ajustar el ecualizador.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final band in params.bands)
                          Expanded(
                            child: _BandSlider(
                              band: band,
                              min: params.minDecibels,
                              max: params.maxDecibels,
                              enabled: enabled,
                            ),
                          ),
                      ],
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

class _BandSlider extends StatelessWidget {
  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final bool enabled;

  const _BandSlider({
    required this.band,
    required this.min,
    required this.max,
    required this.enabled,
  });

  String get _label {
    final hz = band.centerFrequency;
    return hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k'
        : '${hz.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    return StreamBuilder<double>(
      stream: band.gainStream,
      builder: (context, snap) {
        final gain = snap.data ?? band.gain;
        return Column(
          children: [
            const SizedBox(height: 16),
            Text(
              '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: gain.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: enabled
                      ? (v) => player.setBandGain(band, v)
                      : null,
                ),
              ),
            ),
            Text('$_label Hz', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
