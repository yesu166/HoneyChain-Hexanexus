import 'connectivity_service.dart';

/// Fallback used on platforms without a dedicated implementation.
class ConnectivityServiceImpl extends ConnectivityService {
  @override
  Future<void> refresh() async => setOnline(true);
}