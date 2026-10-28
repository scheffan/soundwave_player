import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/radio_station.dart';
import '../services/media_library.dart';
import '../services/player_controller.dart';
import '../services/radio_sources.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import 'radio_search_view.dart';

enum _Filter { all, favorites, recent }

/// Sección Radios: lo único de la app que usa internet.
class RadiosView extends StatefulWidget {
  const RadiosView({super.key});

  @override
  State<RadiosView> createState() => _RadiosViewState();
}

class _RadiosViewState extends State<RadiosView> {
  _Filter _filter = _Filter.all;
  String _query = '';
  bool _searching = false;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<RadioRepository>();
    var list = switch (_filter) {
      _Filter.all => repo.radios,
      _Filter.favorites => repo.favorites,
      _Filter.recent => repo.recent,
    };
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where(
            (r) =>
                r.name.toLowerCase().contains(q) ||
                (r.genre ?? '').toLowerCase().contains(q) ||
                (r.country ?? '').toLowerCase().contains(q),
          )
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Filtrar mis radios',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Radios'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Agregar radios',
            onSelected: _onAddAction,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'link',
                child: ListTile(
                  leading: Icon(Icons.link),
                  title: Text('Pegar link de una radio'),
                ),
              ),
              PopupMenuItem(
                value: 'browse',
                child: ListTile(
                  leading: Icon(Icons.travel_explore),
                  title: Text('Buscar radios del mundo'),
                ),
              ),
              PopupMenuItem(
                value: 'flavibot',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Importar de flavibot'),
                ),
              ),
              PopupMenuItem(
                value: 'fm',
                child: ListTile(
                  leading: Icon(Icons.settings_input_antenna),
                  title: Text('Radio FM (antena)'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final (f, label) in [
                  (_Filter.all, 'Todas (${repo.radios.length})'),
                  (_Filter.favorites, 'Favoritas'),
                  (_Filter.recent, 'Recientes'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          if (_importing) const LinearProgressIndicator(),
          Expanded(
            child: !repo.loaded
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? _EmptyRadios(filter: _filter, onAction: _onAddAction)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: list.length,
                    itemBuilder: (context, i) => RadioTile(radio: list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _onAddAction(String action) async {
    switch (action) {
      case 'link':
        await showRadioEditor(context);
      case 'browse':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RadioSearchView()),
        );
      case 'flavibot':
        await _importFlavibot();
      case 'fm':
        final opened = await MediaLibrary.openFmRadio();
        if (!opened && mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Radio FM'),
              content: const Text(
                'No encontramos una app de radio FM en este teléfono.\n\n'
                'Android no permite que otras apps usen el chip de FM, y muchos teléfonos '
                'nuevos no lo traen. Si tu teléfono tiene radio FM de fábrica, '
                'conectá auriculares con cable (hacen de antena) y abrí esa app.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        }
    }
  }

  Future<void> _importFlavibot() async {
    final repo = context.read<RadioRepository>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      final found = await FlavibotImporter.fetchAll();
      if (found.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos leer las radios de flavibot. '
              'Podés copiar el link de una radio y pegarla con "Pegar link".',
            ),
          ),
        );
      } else {
        final added = await repo.addAll(found);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Se agregaron $added radios nuevas de flavibot.'),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sin conexión. Probá de nuevo cuando tengas internet.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _EmptyRadios extends StatelessWidget {
  final _Filter filter;
  final void Function(String) onAction;

  const _EmptyRadios({required this.filter, required this.onAction});

  @override
  Widget build(BuildContext context) {
    if (filter != _Filter.all) {
      return Center(
        child: Text(
          filter == _Filter.favorites
              ? 'Tocá el ♡ de una radio para tenerla acá.'
              : 'Las radios que escuches van a aparecer acá.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.radio, size: 64, color: AppColors.accent),
        const SizedBox(height: 16),
        const Text(
          'Todavía no tenés radios',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.travel_explore),
          label: const Text('Buscar radios del mundo'),
          onPressed: () => onAction('browse'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Importar de flavibot'),
          onPressed: () => onAction('flavibot'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.link),
          label: const Text('Pegar link de una radio'),
          onPressed: () => onAction('link'),
        ),
      ],
    );
  }
}

class RadioTile extends StatelessWidget {
  final RadioStation radio;

  const RadioTile({super.key, required this.radio});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<RadioRepository>();
    final isCurrent = context.select<PlayerController, bool>(
      (p) => p.currentRadio?.url == radio.url,
    );
    return ListTile(
      leading: RadioLogo(url: radio.favicon),
      title: Text(
        radio.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrent ? AppColors.accent : null,
        ),
      ),
      subtitle: Text(
        radio.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: Icon(
          radio.isFavorite ? Icons.favorite : Icons.favorite_border,
          color: radio.isFavorite ? Colors.pinkAccent : AppColors.textMuted,
        ),
        onPressed: () => repo.toggleFavorite(radio),
      ),
      onTap: () {
        context.read<PlayerController>().playRadio(radio);
        repo.markPlayed(radio);
      },
      onLongPress: () => _showOptions(context),
    );
  }

  void _showOptions(BuildContext context) {
    final repo = context.read<RadioRepository>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                radio.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(radio.url, maxLines: 2),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copiar link'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: radio.url));
                Navigator.pop(sheet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(sheet);
                showRadioEditor(context, existing: radio);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text('Borrar'),
              onTap: () {
                repo.delete(radio);
                Navigator.pop(sheet);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulario para agregar o editar una radio. Si hay un link copiado, lo pega solo.
Future<void> showRadioEditor(
  BuildContext context, {
  RadioStation? existing,
}) async {
  final repo = context.read<RadioRepository>();
  final name = TextEditingController(text: existing?.name);
  final url = TextEditingController(text: existing?.url);
  final genre = TextEditingController(text: existing?.genre);

  if (existing == null) {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (clip != null && clip.startsWith('http')) url.text = clip;
  }
  if (!context.mounted) return;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existing == null ? 'Agregar radio' : 'Editar radio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Link del stream',
                hintText: 'https://…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Pegar',
                  onPressed: () async {
                    final clip = await Clipboard.getData(Clipboard.kTextPlain);
                    if (clip?.text != null) url.text = clip!.text!.trim();
                  },
                ),
              ),
            ),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: genre,
              decoration: const InputDecoration(labelText: 'Género (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (saved != true) return;

  final link = url.text.trim();
  if (!link.startsWith('http')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El link tiene que empezar con http:// o https://'),
        ),
      );
    }
    return;
  }
  final station = RadioStation(
    id: existing?.id,
    name: name.text.trim().isEmpty
        ? (Uri.tryParse(link)?.host ?? link)
        : name.text.trim(),
    url: link,
    genre: genre.text.trim().isEmpty ? null : genre.text.trim(),
    country: existing?.country,
    favicon: existing?.favicon,
    source: existing?.source ?? 'manual',
    isFavorite: existing?.isFavorite ?? false,
    lastPlayed: existing?.lastPlayed,
  );
  existing == null ? await repo.add(station) : await repo.update(station);
}
