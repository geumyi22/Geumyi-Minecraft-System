import 'package:flutter_test/flutter_test.dart';
import 'package:gscm/core/dashboard_controller.dart';

void main() {
  group('realtime transport status', () {
    test('classifies connection-level API failures', () {
      expect(isRealtimeTransportFailureKind('network'), isTrue);
      expect(isRealtimeTransportFailureKind('refused'), isTrue);
      expect(isRealtimeTransportFailureKind('timeout'), isTrue);
      expect(isRealtimeTransportFailureKind('http'), isFalse);
      expect(isRealtimeTransportFailureKind('auth'), isFalse);
      expect(isRealtimeTransportFailureKind('format'), isFalse);
    });

    test('confirmed transport failure overrides an apparently live WebSocket', () {
      expect(
        realtimeIndicatorHealthy(
          realtimeConnected: true,
          disconnectGraceActive: false,
          transportFailure: true,
        ),
        isFalse,
      );
    });

    test('confirmed transport failure overrides disconnect grace', () {
      expect(
        realtimeIndicatorHealthy(
          realtimeConnected: false,
          disconnectGraceActive: true,
          transportFailure: true,
        ),
        isFalse,
      );
    });

    test('short WebSocket loss still uses grace when transport has not failed', () {
      expect(
        realtimeIndicatorHealthy(
          realtimeConnected: false,
          disconnectGraceActive: true,
          transportFailure: false,
        ),
        isTrue,
      );
    });

    test('healthy connected WebSocket remains realtime', () {
      expect(
        realtimeIndicatorHealthy(
          realtimeConnected: true,
          disconnectGraceActive: false,
          transportFailure: false,
        ),
        isTrue,
      );
    });
  });
}
