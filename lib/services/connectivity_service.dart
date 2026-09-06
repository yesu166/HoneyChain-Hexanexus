import 'package:flutter/foundation.dart';

/// Reports whether the device currently has network connectivity.
///
/// Kept as a small abstraction so a real provider (e.g. connectivity_plus or
/// a backend heartbeat) can be swapped in later without touching the UI.
abstract class ConnectivityService extends ChangeNotifier {
  bool _online = true;

  bool get isOnline => _online;

  @protected
  void setOnline(bool value) {
    if (_online != value) {
      _online = value;
      notifyListeners();
    }
  }

  /// Re-evaluates connectivity. Platform implementations decide how.
  Future<void> refresh();
}