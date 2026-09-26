import 'package:flutter_test/flutter_test.dart';
import 'package:gscm/screens/qr_scan_screen.dart';

void main() {
  test('parses GSC 4.2.1 pairing QR', () {
    final result = parseGscmClaim(
      'gscm://pair?host=http%3A%2F%2F100.64.0.1%3A8787&code=12345678',
    );
    expect(result, isNotNull);
    expect(result!.host, 'http://100.64.0.1:8787');
    expect(result.code, '12345678');
    expect(result.hosts, ['http://100.64.0.1:8787']);
  });

  test('accepts optional fallback hosts for forward compatibility', () {
    final result = parseGscmClaim(
      'gscm://pair?host=http%3A%2F%2F100.64.0.1%3A8787&hosts=http%3A%2F%2F100.64.0.1%3A8787%2Chttp%3A%2F%2F192.168.0.20%3A8787&code=12345678',
    );
    expect(result, isNotNull);
    expect(result!.hosts, contains('http://192.168.0.20:8787'));
  });

  test('rejects malformed or non-GSCM QR', () {
    expect(parseGscmClaim('https://example.com/'), isNull);
    expect(parseGscmClaim('gscm://pair?host=http://192.168.0.2:8787&code=1234'), isNull);
  });
}
