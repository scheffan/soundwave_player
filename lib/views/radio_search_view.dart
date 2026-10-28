import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/radio_station.dart';
import '../services/player_controller.dart';
import '../services/radio_sources.dart';
import '../theme.dart';
import '../widgets/artwork.dart';

/// Buscador de radios de todo el mundo (Radio Browser).
class RadioSearchView extends StatefulWidget {
  const RadioSearchView({super.key});

  @override
  State<RadioSearchView> createState() => _RadioSearchViewState();
}

class _RadioSearchViewState extends State<RadioSearchView> {
  static const _countries = {
    'AR': 'Argentina',
    'UY': 'Uruguay',
    'CL': 'Chile',
    'MX': 'México',
    'ES': 'España',
    'US': 'EE.UU.',
    'BR': 'Brasil',
  };

  final _controller = TextEditingController();
  String? _country = 'AR';
  List<RadioStation> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await RadioBrowserApi.search(
        name: _controller.text.trim(),
        countryCode: _country,
      );
      setState(() => _results = results);
    } catch (_) {
      setState(() => _error = 'Sin conexión a internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<RadioRepository>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Nombre de la radio',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Todo el mundo'),
                    selected: _country == null,
                    onSelected: (_) {
                      setState(() => _country = null);
                      _search();
                    },
                  ),
                ),
                for (final e in _countries.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _country == e.key,
                      onSelected: (_) {
                        setState(() => _country = e.key);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                        TextButton(
                          onPressed: _search,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      final saved = repo.contains(r.url);
                      return ListTile(
                        leading: RadioLogo(url: r.favicon),
                        title: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          r.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            saved
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: saved ? AppColors.accent : null,
                          ),
                          tooltip: saved ? 'Ya está en tus radios' : 'Guardar',
                          onPressed: saved ? null : () => repo.add(r),
                        ),
                        onTap: () =>
                            context.read<PlayerController>().playRadio(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
