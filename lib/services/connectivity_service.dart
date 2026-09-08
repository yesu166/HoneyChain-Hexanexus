import 'package:flutter/foundation.dart';

/// Reachability state of the app's backend, combining device network presence
/// and Supabase reachability.
///
/// * [checking] — a probe is in flight or startup has not completed.
/// * [online] — device has a network and the Supabase backend answered.
/// * [offline] — the device has no active network connection.
/// * [serviceError] — the device has network, but Supabase did not answer
///   (backend down, blocked, or a TLS/DNS failure). Kept distinct from
///   [offline] so the UI can explain the two cases differently.
enum ConnectivityStatus { checking, online, offline, serviceError }

/// Reports whether the device currently reaches HoneyChain's backend.
///
/// [isOnline] is a thin alias so existing "online/offline" consumers keep
/// working; UI that needs the exact state uses [status].
abstract class ConnectivityService extends ChangeNotifier {
  ConnectivityStatus _status = ConnectivityStatus.checking;

  ConnectivityStatus get status => _status;

  bool get isOnline => _status == ConnectivityStatus.online;

  @protected
  void setStatus(ConnectivityStatus value) {
    if (_status != value) {
      _status = value;
      notifyListeners();
    }
  }

  /// Re-evaluates connectivity. Platform implementations decide how.
  Future<void> refresh();
}