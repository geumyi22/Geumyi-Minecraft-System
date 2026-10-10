import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

const gscmReleasesApi = 'https://api.github.com/repos/geumyi22/Geumyi-Minecraft-System/releases?per_page=20';

class GscmAppUpdate {
  const GscmAppUpdate({
    required this.version,
    required this.build,
    required this.releaseUrl,
    required this.updateAvailable,
    required this.installedVersion,
    required this.installedBuild,
  });

  final String version;
  final int build;
  final String releaseUrl;
  final bool updateAvailable;
  final String installedVersion;
  final int installedBuild;
}

int compareGscmBuilds(String left, int leftBuild, String right, int rightBuild) {
  List<int> core(String v) {
    final m = RegExp(r'^([0-9]+)[.]([0-9]+)[.]([0-9]+)$').firstMatch(v);
    if (m == null) throw const FormatException('Invalid GSCM version');
    return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  final a = core(left);
  final b = core(right);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return leftBuild.compareTo(rightBuild);
}

// A GitHub "Stable" package is an app-notification source, not a signed
// GSC auto-deployment manifest. Never silently download or install assets.
GscmAppUpdate? findLatestGscmApp(
  Object? response, {
  required String installedVersion,
  required int installedBuild,
}) {
  if (response is! List) throw const FormatException('Invalid GitHub release list');
  final filePattern = RegExp(r'^GSCM-v([0-9]+)[.]([0-9]+)[.]([0-9]+)[+]([0-9]+)-Android[.]apk$');
  final tagPattern = RegExp(r'^[A-Za-z0-9._+-]+$');
  GscmAppUpdate? best;
  for (final item in response) {
    if (item is! Map || item['draft'] != false || item['prerelease'] != false) continue;
    final tag = item['tag_name'];
    if (tag is! String || !tagPattern.hasMatch(tag)) continue;
    final assets = item['assets'];
    if (assets is! List) continue;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String) continue;
      final match = filePattern.firstMatch(name);
      if (match == null || asset['state'] != 'uploaded') continue;
      final size = asset['size'];
      final digest = asset['digest'];
      if (size is! int || size <= 0 || digest is! String ||
          digest.length != 71 || !digest.startsWith('sha256:') ||
          !RegExp(r'^[0-9a-f]+$').hasMatch(digest.substring(7))) {
        continue;
      }
      final remoteVersion = '${match.group(1)}.${match.group(2)}.${match.group(3)}';
      final remoteBuild = int.parse(match.group(4)!);
      final newer = compareGscmBuilds(remoteVersion, remoteBuild, installedVersion, installedBuild) > 0;
      final candidate = GscmAppUpdate(
        version: remoteVersion,
        build: remoteBuild,
        releaseUrl: 'https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/${Uri.encodeComponent(tag)}',
        updateAvailable: newer,
        installedVersion: installedVersion,
        installedBuild: installedBuild,
      );
      if (best == null ||
          compareGscmBuilds(candidate.version, candidate.build, best.version, best.build) > 0) {
        best = candidate;
      }
    }
  }
  return best;
}

class GscmAppUpdateService {
  const GscmAppUpdateService();

  Future<GscmAppUpdate> checkLatest() async {
    final installed = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(installed.buildNumber) ?? 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(gscmReleasesApi))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'GSCM-AppUpdateCheck');
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub 릴리즈 확인 실패 (HTTP ${response.statusCode})');
      }
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 8));
      final latest = findLatestGscmApp(
        jsonDecode(body),
        installedVersion: installed.version,
        installedBuild: currentBuild,
      );
      if (latest == null) {
        throw const FormatException('검증 가능한 공개 GSCM 릴리즈를 찾을 수 없습니다');
      }
      return latest;
    } finally {
      client.close(force: true);
    }
  }
}
