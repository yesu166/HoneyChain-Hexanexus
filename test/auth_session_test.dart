import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/auth.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/services/api_token_store.dart';
import 'package:honeychain/services/local_store.dart';

/// Contract for the canonical session: one session, honest auth states,
/// workspace switching without re-login, and durable restore across restarts.
void main() {
  setUp(() {
    HoneyChainStore.testMode = true;
    SharedPreferences.setMockInitialValues({});
    final store = HoneyChainStore.instance;
    store.ensureStarted();
    store.resetToDemo();
    store.logout();
    store.debugSetOnline(true);
    store.debugResetForTest();
    store.ensureStarted();
  });

  group('auth state', () {
    test('signed out when no session exists', () {
      final store = HoneyChainStore.instance;
      expect(store.loggedIn, isFalse);
      expect(store.authState, AuthState.signedOut);
      expect(store.authStateLabel, 'Signed out');
    });

    test('offline-authenticated when logged in but no backend is compiled in',
        () {
      final store = HoneyChainStore.instance;
      store.completeLogin(phone: '+919999', name: 'Ravi');
      expect(store.loggedIn, isTrue);
      // ApiConfig.isConfigured is false in the test build, so an online demo
      // session is still offline-authenticated — never faked as live backend.
      expect(store.authState, AuthState.offlineAuthenticated);
      expect(store.authStateLabel, contains('No backend configured'));
    });

    test('device offline keeps the session in offline-authenticated', () {
      final store = HoneyChainStore.instance;
      store.completeLogin();
      store.debugSetOnline(false);
      expect(store.authState, AuthState.offlineAuthenticated);
      store.debugSetOnline(true);
    });

    test('logout returns to signed-out but keeps domain data', () {
      final store = HoneyChainStore.instance;
      store.completeLogin(phone: '+919999', name: 'Ravi');
      final harvestCount = store.harvests.length;
      store.recordHarvest(hive: store.hives.first, quantityKg: 3.0);

      store.logout();
      expect(store.loggedIn, isFalse);
      expect(store.authState, AuthState.signedOut);
      expect(store.harvests.length, harvestCount + 1,
          reason: 'logout must not delete local domain records');
      expect(store.activeWorkspace, Workspace.beekeeper);
    });
  });

  group('workspace switching', () {
    test('demo account can enter every persona as a workspace', () {
      final store = HoneyChainStore.instance;
      expect(store.availableWorkspaces, containsAll([
        Workspace.beekeeper,
        Workspace.organization,
        Workspace.buyer,
        Workspace.consumer,
      ]));
    });

    test('switch does not end the session and persists the workspace', () {
      final store = HoneyChainStore.instance;
      store.completeLogin();

      expect(store.switchWorkspace(Workspace.organization), isTrue);
      expect(store.activeWorkspace, Workspace.organization);
      expect(store.loggedIn, isTrue,
          reason: 'switching workspaces must not sign the user out');
      expect(LocalStore.instance.loadActiveWorkspace(), 'organization');
    });

    test('switching back to beekeeper restores the shell workspace', () {
      final store = HoneyChainStore.instance;
      store.switchWorkspace(Workspace.organization);
      expect(store.switchWorkspace(Workspace.beekeeper), isTrue);
      expect(store.activeWorkspace, Workspace.beekeeper);
    });

    test('a workspace not granted to the account is rejected', () async {
      await ApiTokenStore.instance
          .save(const ApiIdentity(
            token: 'jwt-token-2',
            id: 'bk-2',
            email: 'ravi@honeychain.in',
            name: 'Ravi Kumar',
            role: 'beekeeper',
          ));
      await LocalStore.instance.saveLoggedIn(true);

      final store = HoneyChainStore.instance;
      store.debugResetForTest();
      await store.ensureStarted();

      expect(store.backendSignedIn, isTrue);
      expect(store.availableWorkspaces, isNot(contains(Workspace.buyer)));
      expect(store.switchWorkspace(Workspace.buyer), isFalse,
          reason: 'a beekeeper-only account cannot enter the buyer workspace');
      expect(store.activeWorkspace, Workspace.beekeeper);
      await ApiTokenStore.instance.clear();
    });
  });

  group('session restore', () {
    test('persisted FastAPI identity and workspace are restored after restart',
        () async {
      await ApiTokenStore.instance.save(ApiIdentity(
        token: 'jwt-token-1',
        id: 'bk-1',
        email: 'ravi@honeychain.in',
        name: 'Ravi Kumar',
        role: 'beekeeper',
      ));
      await LocalStore.instance.saveLoggedIn(true);
      await LocalStore.instance.saveActiveWorkspace(Workspace.organization.code);

      final store = HoneyChainStore.instance;
      store.debugResetForTest();
      await store.ensureStarted();

      expect(store.loggedIn, isTrue);
      expect(store.backendSignedIn, isTrue,
          reason: 'a persisted JWT must survive an app restart');
      expect(store.backendRole, 'beekeeper');
      expect(store.activeWorkspace, Workspace.organization,
          reason: 'the persisted workspace must be restored');
      // A beekeeper-backed account is narrowed to beekeeper + consumer.
      expect(store.availableWorkspaces, contains(Workspace.beekeeper));
      expect(store.availableWorkspaces, contains(Workspace.consumer));
      expect(store.availableWorkspaces, isNot(contains(Workspace.buyer)));
      await ApiTokenStore.instance.clear();
    });

    test('cleared token restores as signed out', () async {
      await ApiTokenStore.instance.clear();
      await LocalStore.instance.saveLoggedIn(true);

      final store = HoneyChainStore.instance;
      store.debugResetForTest();
      await store.ensureStarted();

      // Login flag is still true locally (offline session) but the backend
      // session is no longer claimed.
      expect(store.loggedIn, isTrue);
      expect(store.backendSignedIn, isFalse);
    });
  });
}