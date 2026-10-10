import 'package:flutter_test/flutter_test.dart';
import 'package:gscm/core/app_update.dart';

Map<String, dynamic> release(String tag, String version, int build, {
  bool draft = false,
  bool prerelease = false,
  String state = 'uploaded',
  String digest = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'assets': [
    {
      'name': 'GSCM-v$version+$build-Android.apk',
      'state': state,
      'size': 12345,
      'digest': digest,
    }
  ]
};

void main() {
  test('version comparator orders major, minor, patch and build', () {
    expect(compareGscmBuilds('1.5.0', 150, '1.5.1', 151), lessThan(0));
    expect(compareGscmBuilds('1.5.0', 150, '1.5.0', 149), greaterThan(0));
    expect(compareGscmBuilds('1.5.0', 150, '1.5.0', 150), 0);
    expect(() => compareGscmBuilds('invalid', 1, '1.5.0', 150), throwsFormatException);
  });
  test('finds latest valid public Stable package', () {
    final a = findLatestGscmApp([
      release('system-2026.10.09-beta', '9.9.9', 999, prerelease: true),
      release('draft', '9.9.8', 998, draft: true),
      release('system-2026.10.11-stable-gsc450-gscm150', '1.5.0', 150),
      release('mc-2026.09.26-v3', '1.1.2', 113),
    ], installedVersion: '1.1.5', installedBuild: 117);
    expect(a?.version, '1.5.0');
    expect(a?.updateAvailable, isTrue);
    expect(a?.releaseUrl, startsWith('https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/'));
  });
  test('does not propose downgrade or incomplete assets', () {
    final a = findLatestGscmApp([
      release('bad', '9.0.0', 900, digest: ''),
      release('bad2', '8.0.0', 800, state: 'starter'),
      release('system-2026.10.11-stable', '1.5.0', 150),
    ], installedVersion: '1.5.1', installedBuild: 151);
    expect(a?.updateAvailable, isFalse);
  });
  test('rejects malformed input and unsafe tags', () {
    expect(() => findLatestGscmApp({}, installedVersion: '1.5.0', installedBuild: 150), throwsFormatException);
    final r = findLatestGscmApp([
      release('../unsafe', '2.0.0', 200),
    ], installedVersion: '1.5.0', installedBuild: 150);
    expect(r, isNull);
  });
}
