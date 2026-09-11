import 'dart:convert';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';

/// Online passport resolution against the public FastAPI endpoint
/// `/api/v1/passport/{subject_code}`.
///
/// This is the real (non-fabricated) provenance path: when a backend URL is
/// compiled in, scanning/typing a code queries the server, which resolves a
/// [PassportProof] from the actual repository records and the Fabric anchor.
/// No result is ever synthesized locally.
class PassportVerificationService {
  PassportVerificationService(this._api);

  final ApiClient _api;

  Future<PassportProof> verify(String subjectCode) async {
    final body = await _api.getJson(
      '/api/v1/passport/${Uri.encodeComponent(subjectCode)}',
    );
    return PassportProof.fromJson(body);
  }
}

enum PassportAnchorStatus {
  anchored,
  pending,
  none;

  static PassportAnchorStatus fromJson(Object? value) =>
      switch (value) {
        'anchored' => PassportAnchorStatus.anchored,
        'pending' => PassportAnchorStatus.pending,
        _ => PassportAnchorStatus.none,
      };
}

enum VerifyOutcome {
  verified,
  unresolved,
  notFound,
  rateLimited,
  unreachable,
  error,
}

class PassportAnchor {
  const PassportAnchor({
    this.dataHash = '',
    this.txHash = '',
    this.chainStatus = 'none',
    this.anchoredAt,
  });

  final String dataHash;
  final String txHash;
  final String chainStatus;
  final String? anchoredAt;

  PassportAnchorStatus get status => PassportAnchorStatus.fromJson(chainStatus);

  factory PassportAnchor.fromJson(Map<String, dynamic> json) => PassportAnchor(
        dataHash: json['data_hash'] as String? ?? '',
        txHash: json['tx_hash'] as String? ?? '',
        chainStatus: json['chain_status'] as String? ?? 'none',
        anchoredAt: json['anchored_at'] as String?,
      );
}

class PassportProof {
  const PassportProof({
    required this.subject,
    required this.subjectCode,
    required this.batchCode,
    this.honeyType = '',
    this.origin = '',
    this.quantityKg = 0,
    this.trustTier = 'self_declared',
    this.anchor = const PassportAnchor(),
  });

  final String subject;
  final String subjectCode;
  final String batchCode;
  final String honeyType;
  final String origin;
  final double quantityKg;
  final String trustTier;
  final PassportAnchor anchor;

  bool get isAnchored => anchor.status == PassportAnchorStatus.anchored;

  factory PassportProof.fromJson(Map<String, dynamic> json) => PassportProof(
        subject: json['subject'] as String? ?? 'batch',
        subjectCode: json['subject_code'] as String? ?? '',
        batchCode: json['batch_code'] as String? ?? '',
        honeyType: json['honey_type'] as String? ?? '',
        origin: json['origin'] as String? ?? '',
        quantityKg: (json['quantity_kg'] as num?)?.toDouble() ?? 0,
        trustTier: json['trust_tier'] as String? ?? 'self_declared',
        anchor: json['anchor'] is Map<String, dynamic>
            ? PassportAnchor.fromJson(json['anchor'] as Map<String, dynamic>)
            : const PassportAnchor(),
      );
}

/// Structured result of an online verification attempt. Every state is
/// honest: nothing is presented as verified unless the server returned a real
/// passport with a real anchor.
class PassportVerificationResult {
  const PassportVerificationResult._({
    required this.outcome,
    this.proof,
    this.message = '',
  });

  final VerifyOutcome outcome;
  final PassportProof? proof;
  final String message;

  bool get verified => outcome == VerifyOutcome.verified && proof != null;

  factory PassportVerificationResult.verified(PassportProof proof) =>
      PassportVerificationResult._(outcome: VerifyOutcome.verified, proof: proof);

  factory PassportVerificationResult.unresolved() => const PassportVerificationResult._(
        outcome: VerifyOutcome.unresolved,
      );

  factory PassportVerificationResult.notFound() =>
      const PassportVerificationResult._(
        outcome: VerifyOutcome.notFound,
        message: 'No Honey Passport exists for this code on the backend.',
      );

  factory PassportVerificationResult.rateLimited() => const PassportVerificationResult._(
        outcome: VerifyOutcome.rateLimited,
        message: 'Too many verification requests — please wait and retry.',
      );

  factory PassportVerificationResult.unreachable(String message) =>
      PassportVerificationResult._(
        outcome: VerifyOutcome.unreachable,
        message: message,
      );

  factory PassportVerificationResult.error(String message) =>
      PassportVerificationResult._(
        outcome: VerifyOutcome.error,
        message: message,
      );
}

/// Runs an online passport verification against the compiled backend. When no
/// backend URL is compiled in the check is [VerifyOutcome.unresolved] — the
/// app never fabricates a verification.
Future<PassportVerificationResult> verifyPassportOnline(
  PassportVerificationService service,
  String subjectCode,
) async {
  try {
    final proof = await service.verify(subjectCode);
    return PassportVerificationResult.verified(proof);
  } on ApiException catch (error) {
    return switch (error.kind) {
      ApiExceptionKind.notFound => PassportVerificationResult.notFound(),
      ApiExceptionKind.unknown when error.statusCode == 429 =>
        PassportVerificationResult.rateLimited(),
      ApiExceptionKind.network ||
      ApiExceptionKind.timeout ||
      ApiExceptionKind.server =>
        PassportVerificationResult.unreachable(friendlyMessage(error)),
      _ => PassportVerificationResult.error(friendlyMessage(error)),
    };
  } on Exception {
    return PassportVerificationResult.unreachable(
      'The backend could not be reached. Only local records are available.',
    );
  }
}

String friendlyMessage(ApiException error) {
  if (error.kind == ApiExceptionKind.network ||
      error.kind == ApiExceptionKind.timeout) {
    return 'The backend could not be reached. Only local records are available.';
  }
  final detail = error.message.trim();
  return detail.isEmpty ? 'Verification failed (${error.kind.name}).' : detail;
}

/// Human-readable label for a [VerifyOutcome] (used by tests and the UI).
String verifyOutcomeLabel(VerifyOutcome outcome) => switch (outcome) {
      VerifyOutcome.verified => 'verified',
      VerifyOutcome.unresolved => 'unavailable',
      VerifyOutcome.notFound => 'not found',
      VerifyOutcome.rateLimited => 'rate limited',
      VerifyOutcome.unreachable => 'unreachable',
      VerifyOutcome.error => 'error',
    };

/// Serializes a [PassportProof] deterministically (stable field order) so the
/// same server payload always hashes to the same string. This mirrors the
/// backend's canonicalisation rule for proving the app and server agree.
String canonicalProofJson(PassportProof proof) {
  final map = <String, dynamic>{
    'subject': proof.subject,
    'subject_code': proof.subjectCode,
    'batch_code': proof.batchCode,
    'honey_type': proof.honeyType,
    'origin': proof.origin,
    'quantity_kg': proof.quantityKg,
    'trust_tier': proof.trustTier,
    'anchor': <String, dynamic>{
      'data_hash': proof.anchor.dataHash,
      'tx_hash': proof.anchor.txHash,
      'chain_status': proof.anchor.chainStatus,
    },
  };
  const encoder = JsonEncoder.withIndent(' ');
  return encoder.convert(map);
}