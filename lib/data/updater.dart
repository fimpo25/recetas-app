import 'dart:convert';
import 'dart:io';

/// Número de compilación y versión, inyectados por CI con --dart-define.
const int appBuild = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
const String appVersion =
    String.fromEnvironment('BUILD_NAME', defaultValue: 'desarrollo');

const String repoSlug = 'fimpo25/recetas-app';
const String releasesPage = 'https://github.com/$repoSlug/releases/latest';

class UpdateInfo {
  final int build;
  final String version;
  final String notes;
  final String apkUrl;
  final int sizeBytes;

  const UpdateInfo({
    required this.build,
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.sizeBytes,
  });

  bool get isNewer => build > appBuild;
}

/// APK que corresponde a este teléfono (64 o 32 bits).
String preferredApkName() {
  final v = Platform.version.toLowerCase();
  if (v.contains('arm64') || v.contains('x64')) return 'recetas-arm64.apk';
  if (v.contains('arm')) return 'recetas-armv7.apk';
  return 'recetas-arm64.apk';
}

/// Número de compilación a partir del tag "v0.1.N".
int buildFromTag(String tag) {
  final last = tag.split('.').last.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(last) ?? 0;
}

/// Primer párrafo del texto del release (las novedades).
String notesFromBody(String body) {
  final first = body.trim().split(RegExp(r'\n\s*\n')).first.trim();
  return first.startsWith('Compilado desde') ? '' : first;
}

/// Consulta el último release publicado en GitHub.
Future<UpdateInfo> fetchLatestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$repoSlug/releases/latest'));
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    req.headers.set(HttpHeaders.userAgentHeader, 'recetas-app');
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('GitHub respondió ${res.statusCode}');
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String?) ?? '';
    final wanted = preferredApkName();
    String? url;
    var size = 0;
    for (final a in (j['assets'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      if (m['name'] == wanted || (url == null && m['name'] == 'recetas-arm64.apk')) {
        url = m['browser_download_url'] as String?;
        size = (m['size'] as num?)?.toInt() ?? 0;
        if (m['name'] == wanted) break;
      }
    }
    return UpdateInfo(
      build: buildFromTag(tag),
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: notesFromBody((j['body'] as String?) ?? ''),
      apkUrl: url ?? releasesPage,
      sizeBytes: size,
    );
  } finally {
    client.close(force: true);
  }
}
