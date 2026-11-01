import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_client/notes_api.dart';

// A made-up value: the tests never touch the real API or a real key.
const fakeKey = 'test-key';

/// What register and login answer.
Map<String, Object?> session(String token, {int id = 456, String name = 'Check A'}) => {
  'token': token,
  'expires_at': '2026-12-01T03:47:06Z',
  'user': {
    'id': id,
    'name': name,
    'email': 'a@example.com',
    'admin': false,
    'enabled': true,
    'created_at': '2026-11-01T03:47:06Z',
    'updated_at': '2026-11-01T03:47:06Z',
  },
};

/// A note as the API answers it.
Map<String, Object?> noteJson(
  int id,
  String title, {
  String? body = 'Text',
  bool pinned = false,
  bool shared = false,
  List<String> tags = const [],
  String? author = 'Check A',
}) => {
  'id': id,
  'user_id': 42,
  'author': author,
  'title': title,
  'body': body,
  'pinned': pinned,
  'shared': shared,
  'tags': tags,
  'created_at': '2026-11-01T03:47:06Z',
  'updated_at': '2026-11-01T03:47:06Z',
};

/// One page of a list, as every list answers.
Map<String, Object?> page(List<Object?> rows) => {'data': rows, 'total': rows.length, 'page': 1, 'per_page': 25};

// All HTTP is mocked; nothing here calls the real API.

/// Builds an API whose HTTP client answers with [handler] and records requests.
(NotesApi, List<http.Request>) apiWith(http.Response Function(http.Request) handler, {String? token, int? userId}) {
  final seen = <http.Request>[];
  final client = MockClient((request) async {
    seen.add(request);
    return handler(request);
  });
  return (NotesApi(apiKey: fakeKey, token: token, userId: userId, client: client), seen);
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response text(String body, int status) => http.Response(body, status, headers: {'content-type': 'text/html'});

/// A logged-in API for user 42.
(NotesApi, List<http.Request>) loggedIn(http.Response Function(http.Request) handler) =>
    apiWith(handler, token: 'tok', userId: 42);

void main() {
  test('sends the key as the apikey query parameter, not as a header', () async {
    final (api, seen) = apiWith((_) => json(session('tok')));
    await api.login(email: 'a@example.com', password: 'secret-pass');

    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.url.host, 'notes.simpleapi.dev');
    expect(r.url.path, '/api/users/login');
    expect(r.url.queryParameters['apikey'], fakeKey);
    expect(r.headers.containsKey('Authorization'), isFalse);
    expect(r.headers.values.any((v) => v.contains(fakeKey)), isFalse);
  });

  test('login stores the token and the user id, and later calls use both', () async {
    final (api, seen) = apiWith((r) {
      if (r.url.path == '/api/users/login') {
        return json(session('tok-1'));
      }
      return json(page([]));
    });
    final result = await api.login(email: 'a@example.com', password: 'secret-pass');
    expect(result.token, 'tok-1');
    expect(result.id, 456);
    expect(result.name, 'Check A');
    expect(jsonDecode(seen.single.body), {'email': 'a@example.com', 'password': 'secret-pass'});

    await api.listNotes();
    final r = seen.last;
    expect(r.url.path, '/api/users/456/notes'); // always the user's own id
    expect(r.headers['Authorization'], 'Bearer tok-1');
  });

  test('login and register never send a bearer token, even if one is set', () async {
    final (api, seen) = apiWith((r) => json(session('tok-new')), token: 'old-tok', userId: 1);
    await api.login(email: 'a@example.com', password: 'secret-pass');
    await api.register(name: 'A', email: 'a@example.com', password: 'secret-pass');
    expect(seen.length, 2);
    expect(seen.every((r) => !r.headers.containsKey('Authorization')), isTrue);
  });

  test('a network failure message names the host and leaks no exception text', () async {
    final api = NotesApi(apiKey: fakeKey, client: MockClient((_) async => throw Exception('socket detail')));
    await expectLater(
      api.login(email: 'a@example.com', password: 'secret-pass'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Could not reach notes.simpleapi.dev. Check your connection and try again.',
        ),
      ),
    );
  });

  test('register sends name, email and password and logs in', () async {
    final (api, seen) = apiWith((_) => json(session('tok-r'), 201));
    final result = await api.register(name: 'Check A', email: 'a@example.com', password: 'secret-pass');

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/users/register');
    expect(jsonDecode(seen.single.body), {'name': 'Check A', 'email': 'a@example.com', 'password': 'secret-pass'});
    expect(result.token, 'tok-r');
    expect(api.loggedIn, isTrue);
    expect(api.userId, 456);
  });

  test('a failed login throws the 401 and stays logged out', () async {
    final (api, _) = apiWith((_) => json({'message': 'Invalid email or password.'}, 401));
    await expectLater(
      api.login(email: 'a@example.com', password: 'wrong-pass'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', 'Invalid email or password.'),
      ),
    );
    expect(api.loggedIn, isFalse);
  });

  test('a duplicate register throws the 409', () async {
    final (api, _) = apiWith(
      (_) => json({'message': 'That email is already registered to this key.'}, 409),
    );
    await expectLater(
      api.register(name: 'A', email: 'a@example.com', password: 'secret-pass'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('a 2xx answer without a token is reported, not treated as a login', () async {
    final (api, _) = apiWith((_) => json({'message': 'Check your email'}));
    final result = await api.login(email: 'a@example.com', password: 'secret-pass');
    expect(result.token, isNull);
    expect(result.message, 'Check your email');
    expect(api.loggedIn, isFalse);
  });

  test('logout posts and forgets the token even when the API refuses', () async {
    final (api, seen) = loggedIn((_) => json({'message': 'Logged out.'}));
    await api.logout();
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/users/logout');
    expect(api.token, isNull);
    expect(api.userId, isNull);

    final (api2, _) = loggedIn((_) => json({'message': 'Invalid or expired auth token. Log in again.'}, 401));
    await expectLater(api2.logout(), throwsA(isA<ApiException>()));
    expect(api2.loggedIn, isFalse);
  });

  test('listSharedNotes needs only the key, even for a logged-in user, and parses the list', () async {
    final (api, seen) = loggedIn(
      (_) => json({
        'data': [
          noteJson(3, 'Packing list', body: 'Charger', shared: true, tags: ['travel'], author: 'Tomas Rivera'),
          noteJson(2, 'Template', body: null, shared: true, tags: [], author: null),
        ],
        'total': 30,
        'page': 1,
        'per_page': 25,
      }),
    );
    final result = await api.listSharedNotes();

    final r = seen.single;
    expect(r.method, 'GET');
    expect(r.url.path, '/api/notes');
    expect(r.url.queryParameters['apikey'], fakeKey);
    expect(r.headers.containsKey('Authorization'), isFalse);
    expect(result.notes.map((n) => n.title), ['Packing list', 'Template']);
    expect(result.notes.first.author, 'Tomas Rivera');
    expect(result.notes.first.tags, ['travel']);
    expect(result.notes.last.author, isNull); // the user is gone
    expect(result.notes.last.body, ''); // a body can be null
    expect(result.total, 30);
    expect(result.hasMore, isTrue);
  });

  test('a blank author counts as none', () {
    expect(Note.fromJson(noteJson(1, 'T', author: '  ')).author, isNull);
  });

  test('hasMore is false on the last page', () {
    expect(NotePage.fromJson({'data': [], 'total': 200, 'page': 2, 'per_page': 100}).hasMore, isFalse);
    expect(NotePage.fromJson({'data': [], 'total': 201, 'page': 2, 'per_page': 100}).hasMore, isTrue);
  });

  test('both lists ask for a full page, and for a free tier user that is every note', () async {
    final (api, seen) = loggedIn((_) => json(page([])));
    await api.listNotes();
    await api.listSharedNotes();
    expect(seen.map((r) => r.url.queryParameters['per_page']), ['100', '100']);
  });

  test('the filters go in the query string, encoded, and an unset filter is left out', () async {
    final (api, seen) = loggedIn((_) => json(page([])));
    await api.listNotes(q: 'rain & wind', tag: 'été', page: 2);
    await api.listSharedNotes(q: 'plan', tag: 'work');
    await api.listNotes();

    expect(seen[0].url.path, '/api/users/42/notes');
    expect(seen[0].url.queryParameters['q'], 'rain & wind');
    expect(seen[0].url.queryParameters['tag'], 'été');
    expect(seen[0].url.queryParameters['page'], '2');
    expect(seen[0].url.queryParameters['apikey'], fakeKey);
    expect(seen[1].url.queryParameters['q'], 'plan');
    expect(seen[1].url.queryParameters['tag'], 'work');
    expect(seen[2].url.queryParameters.keys, unorderedEquals(['apikey', 'page', 'per_page']));
  });

  test('createNote posts every field and parses the answer', () async {
    final (api, seen) = loggedIn((_) => json(noteJson(9, 'Plan', body: 'Text', pinned: true, tags: ['work']), 201));
    final note = await api.createNote(title: 'Plan', body: 'Text', tags: ['work'], pinned: true);

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/users/42/notes');
    expect(seen.single.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(seen.single.body), {
      'title': 'Plan',
      'body': 'Text',
      'tags': ['work'],
      'pinned': true,
      'shared': false,
    });
    expect(note.id, 9);
    expect(note.pinned, isTrue);
  });

  test('createNote leaves out a body it was not given', () async {
    final (api, seen) = loggedIn((_) => json(noteJson(9, 'Plan'), 201));
    await api.createNote(title: 'Plan');
    expect((jsonDecode(seen.single.body) as Map).containsKey('body'), isFalse);
  });

  test('updateNote sends only the fields it was given', () async {
    final (api, seen) = loggedIn((_) => json(noteJson(3260, 'Plan', pinned: true)));
    final note = await api.updateNote(3260, pinned: true);

    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '/api/users/42/notes/3260');
    expect(jsonDecode(seen.single.body), {'pinned': true});
    expect(note.pinned, isTrue);

    await api.updateNote(3260, shared: false);
    expect(jsonDecode(seen.last.body), {'shared': false});

    await api.updateNote(3260, title: 'New', body: 'Text');
    expect(jsonDecode(seen.last.body), {'title': 'New', 'body': 'Text'});
  });

  test('updateNote sends an empty list and an empty body: that is how they are cleared', () async {
    final (api, seen) = loggedIn((_) => json(noteJson(3260, 'Plan')));
    await api.updateNote(3260, tags: [], body: '');
    expect(jsonDecode(seen.single.body), {'tags': [], 'body': ''});
  });

  test('deleteNote uses /notes/{id}', () async {
    final (api, seen) = loggedIn((_) => json({'message': 'Note 3260 deleted.'}));
    await api.deleteNote(3260);

    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/api/users/42/notes/3260');
  });

  test('forgot and reset post the right bodies', () async {
    final (api, seen) = apiWith(
      (r) => r.url.path.endsWith('forgot')
          ? json({'message': 'If an account exists for that email, a reset code has been sent.'})
          : json({'message': 'Password updated.'}),
    );

    expect(await api.forgotPassword('a@example.com'), startsWith('If an account exists'));
    expect(seen.last.url.path, '/api/users/forgot');
    expect(jsonDecode(seen.last.body), {'email': 'a@example.com'});

    await api.resetPassword(email: 'a@example.com', code: '123456', password: 'new-password');
    expect(seen.last.url.path, '/api/users/reset');
    expect(jsonDecode(seen.last.body), {'email': 'a@example.com', 'code': '123456', 'password': 'new-password'});
  });

  test('your-notes calls without a login fail locally, without any request', () async {
    final (api, seen) = apiWith((_) => json(page([])));
    await expectLater(api.listNotes(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(seen, isEmpty);
  });

  group('errors, as the live API really answers', () {
    Future<ApiException> failing(http.Response response) async {
      final (api, _) = loggedIn((_) => response);
      try {
        await api.listNotes();
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('401 missing key: JSON message', () async {
      final e = await failing(
        json({
          'message': 'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=notes',
        }, 401),
      );
      expect(e.statusCode, 401);
      expect(e.message, startsWith('Unauthorized. Please provide a valid apikey'));
    });

    test('401 bad token: JSON message', () async {
      final e = await failing(json({'message': 'Invalid or expired auth token. Log in again.'}, 401));
      expect(e.statusCode, 401);
      expect(e.message, 'Invalid or expired auth token. Log in again.');
    });

    test('404: a JSON message', () async {
      final e = await failing(json({'message': 'Note 999999999 not found.'}, 404));
      expect(e.statusCode, 404);
      expect(e.message, 'Note 999999999 not found.');
    });

    test('400: malformed JSON body', () async {
      final e = await failing(json({'message': 'Malformed JSON body. Send a valid JSON object.'}, 400));
      expect(e.statusCode, 400);
    });

    test('403: a user_id that is not the token\'s user', () async {
      final e = await failing(json({'message': 'The user_id in the path is not the user of this token.'}, 403));
      expect(e.statusCode, 403);
    });

    test('a non-JSON body (not from the API) falls back to a generic message', () async {
      final e = await failing(text('<html>Bad gateway</html>', 502));
      expect(e.statusCode, 502);
      expect(e.message, 'Something went wrong. Please try again.');
    });

    test('403: the per-user note limit', () async {
      final e = await failing(json({'message': 'Free tier limit reached: 100 notes per user.'}, 403));
      expect(e.statusCode, 403);
      expect(e.message, contains('100 notes per user'));
    });

    test('503: the key service is down', () async {
      final e = await failing(json({'message': 'Key service unavailable. Please try again shortly.'}, 503));
      expect(e.statusCode, 503);
    });

    test('422: validation message', () async {
      final e = await failing(json({'message': 'The title field is required.'}, 422));
      expect(e.statusCode, 422);
      expect(e.message, 'The title field is required.');
    });

    test('429 and an empty body fall back to a generic message', () async {
      final e = await failing(http.Response('', 429));
      expect(e.statusCode, 429);
      expect(e.message, 'Something went wrong. Please try again.');
    });
  });

  test('a network failure becomes an ApiException with status 0', () async {
    final api = NotesApi(apiKey: fakeKey, client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(
      api.login(email: 'a@example.com', password: 'secret-pass'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)),
    );
  });
}
