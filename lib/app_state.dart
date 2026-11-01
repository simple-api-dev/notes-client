/// The shared app state: who is logged in.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'notes_api.dart';

/// The app's only shared state: who is logged in. Screens listen to it with
/// [ListenableBuilder]. The API key is the build-time key ([configuredKey]).
class AppState extends ChangeNotifier {
  AppState({String apiKey = configuredKey, http.Client? client}) : api = NotesApi(apiKey: apiKey, client: client);

  /// The client for the build-time key.
  final NotesApi api;
  String? userName;

  bool get loggedIn => api.loggedIn;

  void loggedInAs(String name) {
    userName = name;
    notifyListeners();
  }

  /// POST /api/users/login as the shared demo user. Throws [ApiException] on failure.
  Future<void> loginDemo() async {
    final result = await api.login(email: demoEmail, password: demoPassword);
    if (result.token == null) throw ApiException(401, result.message);
    loggedInAs(result.name.isEmpty ? 'Demo' : result.name);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // The token was already invalid: logging out locally is all that is left.
    }
    userName = null;
    notifyListeners();
  }

  /// The API said our token is no longer valid (401 while logged in): drop it.
  void sessionExpired() {
    if (!api.loggedIn) return;
    api.token = null;
    api.userId = null;
    userName = null;
    notifyListeners();
  }
}
