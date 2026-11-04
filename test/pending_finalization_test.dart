import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finalized_graph_open_test.dart' show finalizedResponse;

Map<String, dynamic> pending() {
  final value = finalizedResponse();
  value['etag'] = 'pending-etag';
  (value['finalization'] as Map)['receiptVerified'] = false;
  (value['graph']['_opsFinalization'] as Map).remove('receiptVerified');
  return value;
}

void main() {
  test('pending receipt never returns an editable package', () {
    expect(() => PortalGraphPackage.fromResponse(pending()),
        throwsA(isA<PortalFinalizationPendingException>()));
  });
  test('pending without authoritative etag fails closed', () {
    final value = pending()..remove('etag');
    expect(() => PortalGraphPackage.fromResponse(value),
        throwsA(isA<PortalFinalizationException>()));
  });
  test('receipt retry rereads lock, uses exact etag and verifies fresh receipt',
      () async {
    var loads = 0, repairs = 0;
    final result = await recoverPendingGraphFinalization(
        load: () async => PortalGraphPackage.fromResponse(
            ++loads == 1 ? pending() : finalizedResponse()),
        repair: (etag) async {
          expect(etag, 'pending-etag');
          repairs++;
        });
    expect(result.isFinalized, true);
    expect(loads, 2);
    expect(repairs, 1);
    expect(result.blobs['full-photo'], [1, 2, 3]);
    expect(result.blobs['thumbnail'], [4, 5]);
  });
  test('already verified receipt needs no repair', () async {
    await recoverPendingGraphFinalization(
        load: () async => PortalGraphPackage.fromResponse(finalizedResponse()),
        repair: (_) async => fail('Unnecessary mutation'));
  });
  for (final scenario in ['pending', 'unlocked', 'changed', 'auth']) {
    test('retry never reports success for $scenario reload', () async {
      var loads = 0;
      expect(
          recoverPendingGraphFinalization(
              load: () async {
                if (++loads == 1) {
                  return PortalGraphPackage.fromResponse(pending());
                }
                if (scenario == 'auth') {
                  throw const PortalAuthenticationException(
                      'https://example.invalid');
                }
                final value =
                    scenario == 'pending' ? pending() : finalizedResponse();
                if (scenario == 'unlocked') {
                  value.remove('finalization');
                  (value['graph'] as Map).remove('_opsFinalization');
                }
                if (scenario == 'changed') {
                  (value['finalization'] as Map)['snapshotSha256'] = 'b' * 64;
                  (value['graph']['_opsFinalization']
                      as Map)['snapshotSha256'] = 'b' * 64;
                }
                return PortalGraphPackage.fromResponse(value);
              },
              repair: (_) async {}),
          throwsA(isA<Exception>()));
    });
  }
  test('initial auth failure performs zero repair writes', () async {
    var repairs = 0;
    await expectLater(
        recoverPendingGraphFinalization(
            load: () async => throw const PortalAuthenticationException(
                'https://example.invalid'),
            repair: (_) async {
              repairs++;
            }),
        throwsA(isA<PortalAuthenticationException>()));
    expect(repairs, 0);
  });
}
