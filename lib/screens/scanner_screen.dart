import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/honeychain_store.dart';
import '../services/trace_qr_service.dart';

/// Camera-based QR scanner for the canonical HoneyChain payloads
/// (`honeychain://trace/<code>` and legacy `honeychain://jar/<id>`).
///
/// Honest error handling: permission / camera failures show guidance plus a
/// manual-entry fallback instead of pretending the scan worked.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.onResolved});

  /// Called with the resolved target once a valid code is detected. When
  /// null, the resolution is returned via `Navigator.pop`. [raw] carries the
  /// exact scanned string so callers can run their own (e.g. online passport)
  /// lookup when the local registry has no record.
  final Future<void> Function(ScanResolution resolution, {String? raw})?
      onResolved;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handlingScan = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handlingScan) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (raw == null || raw.trim().isEmpty) return;
    _handlingScan = true;
    await _controller.stop();
    await _resolve(raw);
  }

  Future<void> _resolve(String raw) async {
    final store = HoneyChainStore.instance;
    final resolution = store.resolveScan(raw);
    if (!mounted) return;

    if (resolution is ScanResolutionUnknown) {
      // Unknown locally, but the caller (consumer flow) may still resolve it
      // online against the backend passport registry.
      if (widget.onResolved != null) {
        await widget.onResolved!(resolution, raw: raw);
        return;
      }
      setState(() => _handlingScan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resolution.reason)),
      );
      await _controller.start();
      return;
    }

    if (widget.onResolved != null) {
      await widget.onResolved!(resolution, raw: raw);
      return;
    }
    Navigator.of(context).pop(resolution);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Honey Passport QR'),
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _ErrorPanel(
                message: _describe(error),
                onRetry: () async {
                  if (error.errorCode ==
                      MobileScannerErrorCode.permissionDenied) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Allow camera access in your device settings, '
                          'then reopen scanning.',
                        ),
                      ),
                    );
                  }
                  await _controller.start();
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('Enter the code manually instead'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _describe(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera permission was denied. Allow camera access for this '
            'app in your device settings, then tap Retry.';
      case MobileScannerErrorCode.unsupported:
        return 'QR scanning is not supported on this device. Use manual '
            'code entry instead.';
      case MobileScannerErrorCode.genericError:
        return 'The camera could not start. Tap Retry, or enter the code '
            'manually.';
      default:
        return 'The camera could not start (${error.errorCode.name}). Tap '
            'Retry, or enter the code manually.';
    }
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: Colors.white70, size: 44),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry camera'),
          ),
        ],
      ),
    );
  }
}