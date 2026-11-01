// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String supabaseUrl = 'https://uurejujwjaxzwnjpsrrz.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_isqVWcsXnxihYSO4rwBqCQ_ieeVE4lw';

  static const String googleWebClientId =
      '770149348902-m0d6id81ojka4tohae7udkj0b9eqqobm.apps.googleusercontent.com';

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: googleWebClientId,
    scopes: ['email', 'profile'],
  );

  SupabaseClient get _client => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  String? get displayName =>
      currentUser?.userMetadata?['full_name'] ??
      currentUser?.userMetadata?['name'];
  String? get email => currentUser?.email;
  String? get avatarUrl =>
      currentUser?.userMetadata?['avatar_url'] ??
      currentUser?.userMetadata?['picture'];

  Future<String?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return 'cancelled';

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        return 'Google sign-in failed: no ID token returned.';
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] signIn error: $e');
      return 'Sign-in failed: $e';
    }
  }

  Future<String?> freshGoogleIdToken() async {
    try {
      GoogleSignInAccount? account =
          await _googleSignIn.signInSilently(reAuthenticate: true);
      account ??= await _googleSignIn.signIn();
      if (account == null) return null;
      return (await account.authentication).idToken;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] freshGoogleIdToken error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _client.auth.signOut();
  }

  Future<String?> deleteAllUserData() async {
    final uid = currentUser?.id;
    if (uid == null) return 'Not signed in.';

    const tables = [
      'favorites',
      'playlists',
      'followed_artists',
      'followed_albums',
      'history',
    ];

    final failed = <String>[];
    for (final table in tables) {
      try {
        await _client.from(table).delete().eq('user_id', uid);
      } catch (e) {
        if (kDebugMode) debugPrint('[AuthService] delete "$table" failed: $e');
        failed.add(table);
      }
    }

    if (failed.isNotEmpty) {
      return 'Some data could not be deleted (${failed.join(', ')}). '
          'Check your connection and try again.';
    }

    return null;
  }
}
