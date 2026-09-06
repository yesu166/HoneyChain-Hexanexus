import 'connectivity_impl_stub.dart'
    if (dart.library.io) 'connectivity_impl_io.dart'
    if (dart.library.html) 'connectivity_impl_web.dart';
import 'connectivity_service.dart';

/// Creates the platform-appropriate connectivity service.
ConnectivityService createConnectivityService() => ConnectivityServiceImpl();