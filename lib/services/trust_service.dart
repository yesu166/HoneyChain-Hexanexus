import '../models/domain.dart';
import '../repositories/local_honeychain_repository.dart';

/// Derives an explicit [TrustTier] from a batch's persisted records.
///
/// The service is the single source of truth for trust evaluation so the UI,
/// developer tooling and tests all agree on what a tier means and what it
/// does NOT prove.
class TrustService {
  TrustService(this.repository);
  final HoneychainRepository repository;

  TrustState evaluate(Batch batch) {
    final custody = repository.custodyForBatch(batch.id);
    final verifications = repository.verificationsForBatch(batch.id);
    final anchors = repository.anchorsForBatch(batch.id);
    final links = repository.harvestsForBatch(batch.id);

    final passes =
        verifications.where((v) => v.status == VerificationStatus.pass);
    final fails =
        verifications.where((v) => v.status == VerificationStatus.fail);

    final claims = <String>[];
    if (links.isNotEmpty) {
      claims.add('Attached harvest records: ${links.length} (beekeeper-reported).');
    }
    if (custody.isNotEmpty) {
      claims.add('Custody accepted by the collection organization.');
    }
    if (passes.isNotEmpty) {
      claims.add('Laboratory verification passed (moisture & sugar profile).');
    }
    if (fails.isNotEmpty) {
      claims.add('A laboratory verification did not pass.');
    }

    final anchor = anchors.isNotEmpty ? anchors.first : null;
    final isMockAnchor = anchor?.isMock ?? false;
    final anchored = anchor != null;

    final caveats = <String>[];
    if (anchored && isMockAnchor) {
      caveats.add(
        'Integrity anchoring is on prototype mock infrastructure - not a '
        'production blockchain. Shown for demonstration only.',
      );
    }
    if (fails.isNotEmpty && passes.isNotEmpty) {
      caveats.add(
        'Batch passed a later laboratory test after an earlier failure.',
      );
    }
    caveats.add(
      'A trust tier does NOT certify purity, taste, nutrition or health claims.',
    );

    final tier = anchored
        ? TrustTier.blockchainAnchored
        : passes.isNotEmpty
            ? TrustTier.labVerified
            : custody.isNotEmpty
                ? TrustTier.organizationVerified
                : TrustTier.selfDeclared;

    return TrustState(
      tier: tier,
      claims: claims,
      caveats: caveats,
      passCount: passes.length,
      failCount: fails.length,
      custodyCount: custody.length,
      anchorCount: anchors.length,
      isPrototypeAnchor: isMockAnchor,
    );
  }

  /// A child produced by a physical split inherits the parent's tier: the
  /// verification proof applies to the lot the child was taken from.
  TrustState inheritOnSplit(Batch parent) {
    final state = evaluate(parent);
    return TrustState(
      tier: state.tier,
      claims: state.claims,
      caveats: [
        ...state.caveats,
        'Split from ${parent.code}; inherits its verified history.',
      ],
      passCount: state.passCount,
      failCount: state.failCount,
      custodyCount: state.custodyCount,
      anchorCount: state.anchorCount,
      isPrototypeAnchor: state.isPrototypeAnchor,
    );
  }

  /// Merging lots creates a new batch that can only be as trustworthy as the
  /// least trusted child (weakest link) - enforced here, never in the UI.
  TrustTier mergeTier(Iterable<Batch> children) {
    var tier = TrustTier.blockchainAnchored;
    for (final child in children) {
      final t = evaluate(child).tier;
      if (t.rank < tier.rank) tier = t;
    }
    return tier;
  }
}