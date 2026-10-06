import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../screens/honey_passport_screen.dart';

/// A real Honey Yatra QR encoding the deterministic trace handle of an individual
/// jar (`honeychain://jar/<jarId>`), which a consumer scans or pastes to open
/// the jar's Honey Passport.
///
/// The QR does not embed the full genealogy; it encodes a stable trace handle
/// that resolves to the jar and its full supply-chain history (harvests,
/// lab verification, blockchain anchor, marketplace listing). The payload is
/// environment-independent so the same QR is valid on web, mobile, and in the
/// demo.
class JarQrWidget extends StatelessWidget {
  const JarQrWidget({
    super.key,
    required this.jar,
    this.size = 140,
  });

  final HoneyJar jar;
  final double size;

  /// The deterministic trace handle the QR encodes.
  String traceUrl() {
    return jar.qrPayload.isNotEmpty
        ? jar.qrPayload
        : 'honeychain://jar/${jar.jarId}';
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final url = traceUrl();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF2E2417),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF2E2417),
            ),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 6),
          Text(
            jar.jarId,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HoneyPassportScreen(
                  batch: store.batchById(jar.sourceBatchId),
                  jar: jar,
                ),
              ),
            ),
            child: Text(
              store.tr('qr.tap.passport'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.orangeDark,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

