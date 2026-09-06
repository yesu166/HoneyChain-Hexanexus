import 'dart:io';

import 'connectivity_service.dart';

/// Real network check for mobile and desktop (dart:io).
class ConnectivityServiceImpl extends ConnectivityService {
  @override
  Future<void> refresh() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      setOnline(result.isNotEmpty && result.first.rawAddress.isNotEmpty);
    } catch (_) {
      setOnline(false);
    }
  }
}