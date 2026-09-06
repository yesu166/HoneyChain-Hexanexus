import 'package:web/web.dart' as web;

import 'connectivity_service.dart';

/// Web implementation using the browser's online status.
class ConnectivityServiceImpl extends ConnectivityService {
  @override
  Future<void> refresh() async {
    setOnline(web.window.navigator.onLine);
  }
}