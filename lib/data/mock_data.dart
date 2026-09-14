import '../models/honey_batch.dart';

class MockData {
  /// Shared demo batch used by legacy role screens (e.g. beekeeper dashboard).
  static final HoneyBatch batch = demoBatch();

  static HoneyBatch demoBatch() {
    return const HoneyBatch(
      id: 'HC-2026-003',
      honeyType: 'Multifloral Honey',
      beekeeper: 'Ravi Kumar',
      origin: 'Tamil Nadu',
      harvestDate: '24 Aug 2026',
      quantity: 25,
      custodyStatus: 'accepted',
      labStatus: 'verified',
      authenticityStatus: 'verified',
      // Deliberately empty: a demo MUST NOT carry a fabricated hash. A real
      // transaction hash is only ever displayed when the backend returns one.
      blockchainStatus: 'committed',
      blockchainHash: '',
      labResults: {
        'moisture': '17.2% — within expected range',
        'sugarProfile': 'Consistent with natural honey',
        'authenticity': 'No indicators of adulteration',
      },
      events: [
        HoneyEvent(
          type: 'REGISTER',
          actor: 'Beekeeper',
          timestamp: '24 Aug 2026, 08:15',
          status: 'Completed',
          description: 'Batch registered with HoneyChain.',
        ),
        HoneyEvent(
          type: 'CUSTODY',
          actor: 'Collection / Processor',
          timestamp: '25 Aug 2026, 11:40',
          status: 'Completed',
          description: 'Custody accepted from beekeeper.',
        ),
        HoneyEvent(
          type: 'LAB_VERIFY',
          actor: 'Regional Laboratory',
          timestamp: '27 Aug 2026, 16:05',
          status: 'Verified',
          description: 'Laboratory verification completed — authenticity PASS.',
        ),
        HoneyEvent(
          type: 'ANCHOR',
          actor: 'HoneyChain Integrity Layer',
          timestamp: '27 Aug 2026, 16:09',
          status: 'Committed',
          description: 'Verification evidence committed to the on-device '
              'integrity log (demo). No blockchain hash is fabricated.',
        ),
      ],
    );
  }
}
