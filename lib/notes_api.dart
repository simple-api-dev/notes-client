/// The whole Notes API client. Every network call in the app is in this file.
///
/// Docs: https://notes.simpleapi.dev/docs
///
/// Two rules apply to every request:
///  * the API key goes in the `apikey` query string (an `APIKEY` header also works);
///  * a logged-in user also sends `Authorization: Bearer <token>`, where the
///    token comes from [NotesApi.register] / [NotesApi.login]. Those two calls
///    never send a bearer token themselves.
///
/// Shared notes need only the key. A user's own notes are the per-user calls
/// (`/api/users/{user_id}/...`). The `{user_id}` is always the logged-in user's
/// own id, taken from the register / login answer, never typed in or guessed.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

export 'models.dart';

class NotesApi {
  NotesApi({required this.apiKey, this.token, this.userId, http.Client? client, this.host = 'notes.simpleapi.dev'})
    : _http = client ?? http.Client();

  final String apiKey;
  final String host;

  /// Set after [login] / [register]; sent as the Bearer token.
  String? token;

  /// The logged-in user's own id; used in every `/api/users/{user_id}/...` path.
  int? userId;

  final http.Client _http;

  /// Rows on a page. A free tier user holds up to 100 notes, so one page shows them all.
  static const perPage = 100;

  bool get loggedIn => token != null && userId != null;

  // ------------------------------------------------------------------ users

  /// POST /api/users/register - create a user that belongs to this key and log
  /// in as it. A key holds 25 users; passwords need 8+ characters and the email
  /// a dotted domain. A new user answers 201 with `{token, expires_at, user}`.
  /// An email that is already registered answers 409.
  Future<AuthResult> register({required String name, required String email, required String password}) async {
    final json = await _send(
      'POST',
      '/api/users/register',
      authenticated: false,
      body: {'name': name, 'email': email, 'password': password},
    );
    return _authResult(json);
  }

  /// POST /api/users/login - answers `{token, expires_at, user}`. A wrong email
  /// or password answers 401 "Invalid email or password.".
  Future<AuthResult> login({required String email, required String password}) async {
    final json = await _send(
      'POST',
      '/api/users/login',
      authenticated: false,
      body: {'email': email, 'password': password},
    );
    return _authResult(json);
  }

  /// POST /api/users/logout - ends this session. Other sessions of the user
  /// stay logged in.
  Future<void> logout() async {
    try {
      await _send('POST', '/api/users/logout');
    } finally {
      token = null;
      userId = null;
    }
  }

  AuthResult _authResult(Map<String, dynamic> json) {
    final t = json['token'];
    final user = json['user'];
    final id = user is Map ? user['id'] : null;
    if (t is String && t.isNotEmpty && id is num) {
      token = t;
      userId = id.toInt();
      return AuthResult(token: t, id: userId, name: '${user['name'] ?? ''}');
    }
    return AuthResult(message: '${json['message'] ?? 'No token was returned.'}');
  }

  /// POST /api/users/forgot - emails a 6-digit reset code. The answer is the
  /// same whether or not the address has an account.
  Future<String> forgotPassword(String email) async {
    final json = await _send('POST', '/api/users/forgot', body: {'email': email});
    return '${json['message'] ?? 'If an account exists for that email, a reset code has been sent.'}';
  }

  /// POST /api/users/reset - sets a new password using the emailed code.
  Future<String> resetPassword({required String email, required String code, required String password}) async {
    final json = await _send('POST', '/api/users/reset', body: {'email': email, 'code': code, 'password': password});
    return '${json['message'] ?? 'Password updated.'}';
  }

  // ------------------------------------------------------------- shared notes

  /// GET /api/notes - the shared notes, newest first. Only the key is needed,
  /// so this never sends a bearer token. `q` matches the title or body and
  /// `tag` matches one tag.
  Future<NotePage> listSharedNotes({String? q, String? tag, int page = 1}) async {
    final json = await _send('GET', '/api/notes', authenticated: false, query: _listQuery(q, tag, page));
    return NotePage.fromJson(json);
  }

  // --------------------------------------------------------------- your notes
  // Everything below needs a logged-in user (Bearer token).

  /// GET /api/users/{user_id}/notes - the logged-in user's notes, pinned first,
  /// then newest first. Takes the same filters as [listSharedNotes].
  Future<NotePage> listNotes({String? q, String? tag, int page = 1}) async {
    final json = await _send('GET', '$_userPath/notes', query: _listQuery(q, tag, page));
    return NotePage.fromJson(json);
  }

  /// POST /api/users/{user_id}/notes - add a note (a user may have 100; the
  /// 101st is refused with 403). The API lowercases the tags.
  Future<Note> createNote({
    required String title,
    String? body,
    List<String> tags = const [],
    bool pinned = false,
    bool shared = false,
  }) async {
    final json = await _send(
      'POST',
      '$_userPath/notes',
      body: {'title': title, 'body': ?body, 'tags': tags, 'pinned': pinned, 'shared': shared},
    );
    return Note.fromJson(json);
  }

  /// PUT /api/users/{user_id}/notes/{id} - only the fields sent change, so null
  /// here means "leave it alone". An empty [tags] list clears the tags.
  Future<Note> updateNote(int id, {String? title, String? body, List<String>? tags, bool? pinned, bool? shared}) async {
    final json = await _send(
      'PUT',
      '$_userPath/notes/$id',
      body: {'title': ?title, 'body': ?body, 'tags': ?tags, 'pinned': ?pinned, 'shared': ?shared},
    );
    return Note.fromJson(json);
  }

  /// DELETE /api/users/{user_id}/notes/{id} - delete one of your notes.
  Future<void> deleteNote(int id) async {
    await _send('DELETE', '$_userPath/notes/$id');
  }

  Map<String, String> _listQuery(String? q, String? tag, int page) => {
    'q': ?q,
    'tag': ?tag,
    'page': '$page',
    'per_page': '$perPage',
  };

  String get _userPath {
    final id = userId;
    if (id == null) throw ApiException(401, 'Please log in first.');
    return '/api/users/$id';
  }

  // ---------------------------------------------------------------- plumbing

  /// Sends one request and returns the decoded JSON object.
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.https(host, path, {'apikey': apiKey, ...?query});
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers.addAll({if (authenticated && token != null) 'Authorization': 'Bearer $token'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw ApiException(0, 'Could not reach $host. Check your connection and try again.');
    }

    final text = response.body.trim();
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        // Every API answer is JSON. Anything else (a proxy's error page, say)
        // gets the generic message below.
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, _errorMessage(response.statusCode, decoded));
    }
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  /// Every error from the API is JSON: `{"message": "..."}`.
  String _errorMessage(int status, Object? decoded) {
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'Something went wrong. Please try again.';
  }
}
