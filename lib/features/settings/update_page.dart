import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../data/updater.dart';
import '../../domain/text.dart';

const _lastCheckKey = 'update_last_check';

/// Abre la descarga del APK en el navegador; Android ofrece instalarlo al terminar.
Future<void> openDownload(BuildContext context, UpdateInfo u) async {
  final ok = await launchUrl(Uri.parse(u.apkUrl),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showSnack(context, 'No se pudo abrir el navegador.');
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo u) {
  final size = u.sizeBytes > 0 ? ' · ${fmtNum(u.sizeBytes / 1e6, decimals: 0)} MB' : '';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Versión ${u.version} disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tenés la $appVersion.$size'),
          if (u.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Novedades', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(u.notes),
          ],
          const SizedBox(height: 12),
          const Text(
            'Se descarga con el navegador. Al terminar, tocá la descarga e instalá: tus datos se conservan.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Ahora no')),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            openDownload(context, u);
          },
          icon: const Icon(Icons.download),
          label: const Text('Descargar'),
        ),
      ],
    ),
  );
}

/// Chequeo silencioso al abrir la app, como mucho una vez cada 12 horas.
Future<void> autoCheckForUpdate(BuildContext context) async {
  if (appBuild == 0) return; // compilación local de desarrollo
  try {
    final repo = Repo.instance;
    final last = int.tryParse(await repo.setting(_lastCheckKey) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 12).inMilliseconds) return;
    final u = await fetchLatestRelease();
    await repo.setSetting(_lastCheckKey, '$now');
    if (u.isNewer && context.mounted) await showUpdateDialog(context, u);
  } catch (_) {
    // Sin conexión o GitHub no responde: se reintenta la próxima vez.
  }
}

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  bool _checking = false;
  UpdateInfo? _latest;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final u = await fetchLatestRelease();
      await Repo.instance.setSetting(
          _lastCheckKey, '${DateTime.now().millisecondsSinceEpoch}');
      if (!mounted) return;
      setState(() => _latest = u);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo consultar GitHub. Revisá la conexión.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = _latest;
    return Scaffold(
      appBar: AppBar(title: const Text('Actualizaciones')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Versión instalada: $appVersion', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_checking)
            const Row(children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Buscando actualizaciones…'),
            ])
          else if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          else if (u != null && u.isNewer) ...[
            Text('Hay una versión nueva: ${u.version}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
            if (u.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(u.notes),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => openDownload(context, u),
              icon: const Icon(Icons.download),
              label: const Text('Descargar e instalar'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Al terminar la descarga, tocala e instalá encima. Tus recetas y el plan se conservan.',
              style: TextStyle(fontSize: 12),
            ),
          ] else if (u != null)
            const Row(children: [
              Icon(Icons.check_circle_outline),
              SizedBox(width: 8),
              Text('Tenés la última versión.'),
            ]),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('Buscar de nuevo'),
          ),
        ],
      ),
    );
  }
}
