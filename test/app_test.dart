import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_client/app.dart';
import 'package:notes_client/app_state.dart';
import 'package:notes_client/screens/ui.dart';

// All HTTP is mocked; nothing here calls the real API.

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const authAnswer = {
  'token': 'tok',
  'expires_at': '2026-12-01T03:47:06Z',
  'user': {
    'id': 42,
    'name': 'Ann',
    'email': 'ann@example.com',
    'admin': false,
    'enabled': true,
    'created_at': '2026-11-01T03:47:06Z',
    'updated_at': '2026-11-01T03:47:06Z',
  },
};

Map<String, Object?> noteJson(
  int id,
  String title, {
  String? body = 'Some text',
  bool pinned = false,
  bool shared = false,
  List<String> tags = const [],
  String? author = 'Ann',
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
Map<String, Object?> page(List<Object?> rows, {int? total, int page = 1, int perPage = 100}) => {
  'data': rows,
  'total': total ?? rows.length,
  'page': page,
  'per_page': perPage,
};

/// Links the app asked to open.
final opened = <String>[];

/// Pumps the whole app against a fake server and records the requests.
/// [buildKey] stands in for the key passed with --dart-define at build time.
Future<List<http.Request>> pumpApp(
  WidgetTester tester, {
  String buildKey = 'build-key',
  required FutureOr<http.Response> Function(http.Request) server,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  opened.clear();
  final seen = <http.Request>[];
  final client = MockClient((r) async {
    seen.add(r);
    return server(r);
  });
  final state = AppState(apiKey: buildKey, client: client);
  await tester.pumpWidget(NotesApp(state: state, openUrl: opened.add));
  if (settle) await tester.pumpAndSettle();
  return seen;
}

/// A tiny in-memory Notes API: the shared notes, and the notes of user 42.
class FakeServer {
  FakeServer({List<Map<String, Object?>>? shared, List<Map<String, Object?>>? notes})
    : shared = [...?shared],
      notes = [...?notes];

  final List<Map<String, Object?>> shared;
  final List<Map<String, Object?>> notes;
  int nextId = 100;
  http.Response? failNext;
  http.Response? failNextList;

  /// As the API does: `q` looks in the title and body, `tag` matches one tag.
  List<Map<String, Object?>> _filter(List<Map<String, Object?>> rows, http.Request r) {
    final q = r.url.queryParameters['q']?.toLowerCase();
    final tag = r.url.queryParameters['tag'];
    return [
      for (final note in rows)
        if ((q == null || '${note['title']} ${note['body']}'.toLowerCase().contains(q)) &&
            (tag == null || (note['tags'] as List).contains(tag)))
          note,
    ];
  }

  http.Response call(http.Request r) {
    final fail = failNext;
    if (fail != null && r.url.path.startsWith('/api/users/42/')) {
      failNext = null;
      return fail;
    }
    final path = r.url.path;
    final failList = failNextList;
    if (failList != null && r.method == 'GET') {
      failNextList = null;
      return failList;
    }
    if (path == '/api/users/login') return json(authAnswer);
    if (path == '/api/users/register') return json(authAnswer, 201);
    if (path == '/api/users/logout') return json({'message': 'Logged out.'});
    if (path == '/api/notes') return json(page(_filter(shared, r)));
    if (path == '/api/users/42/notes' && r.method == 'GET') {
      // pinned first, then newest first
      final rows = _filter(notes, r)
        ..sort((a, b) {
          final pinned = (b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0);
          return pinned != 0 ? pinned : (b['id'] as int) - (a['id'] as int);
        });
      return json(page(rows));
    }
    if (path == '/api/users/42/notes' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, Object?>;
      final note = {...noteJson(nextId++, body['title'] as String), ...body};
      notes.add(note);
      return json(note, 201);
    }
    final one = RegExp(r'^/api/users/42/notes/(\d+)$').firstMatch(path);
    if (one != null) {
      final id = int.parse(one.group(1)!);
      final i = notes.indexWhere((n) => n['id'] == id);
      if (i < 0) return json({'message': 'Note $id not found.'}, 404);
      if (r.method == 'PUT') {
        // only the fields sent change
        notes[i] = {...notes[i], ...(jsonDecode(r.body) as Map<String, Object?>)};
        return json(notes[i]);
      }
      if (r.method == 'DELETE') {
        notes.removeAt(i);
        return json({'message': 'Note $id deleted.'});
      }
    }
    return json({'message': 'This route does not exist.'}, 404);
  }
}

Finder appBarLogIn() => find.widgetWithText(TextButton, 'Log in');

Future<void> logIn(WidgetTester tester, {bool register = false}) async {
  await tester.tap(appBarLogIn());
  await tester.pumpAndSettle();
  if (register) {
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ann');
  }
  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
  await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret-pass');
  await tester.tap(find.widgetWithText(FilledButton, register ? 'Register' : 'Log in'));
  await tester.pumpAndSettle();
}

/// The tooltip button on the card of the note with this title.
Finder onCard(String title, String tooltip) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
  matching: find.byTooltip(tooltip),
);

/// Types in the search box and lets the pause before the search run out.
Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.widgetWithText(TextField, 'Search notes'), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> saveDialog(WidgetTester tester) async {
  await tester.pump(); // Save turns on once there is a title
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

Map<String, Object?> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, Object?>;

Iterable<String> requests(List<http.Request> seen) => seen.map((r) => '${r.method} ${r.url.path}');

/// The login screen every SimpleAPI demo shares: same order, same widths, and no overflow at 360px.
Future<void> expectSharedLoginLayout(WidgetTester tester) async {
  final demo = find.widgetWithText(FilledButton, 'Try the demo account');
  final logIn = find.widgetWithText(FilledButton, 'Log in');
  final order = [
    demo,
    find.byType(Divider),
    find.text(demoNoticeText),
    find.widgetWithText(TextField, 'Email'),
    find.widgetWithText(TextField, 'Password'),
    logIn,
  ];
  final tops = [for (final item in order) tester.getTopLeft(item).dy];
  expect(tops, [...tops]..sort());
  expect(tester.getTopLeft(find.widgetWithText(TextButton, 'Create an account')).dy, greaterThanOrEqualTo(tops.last));

  expect(tester.getSize(demo).width, 512); // 560 wide with 24 of padding
  expect(tester.getSize(find.widgetWithText(TextField, 'Email')).width, 512);
  expect(tester.getSize(logIn).width, lessThan(512));

  tester.view.physicalSize = const Size(360, 800);
  await tester.pump();
  expect(tester.getSize(demo).width, 312);
}

void main() {
  final sharedNote = noteJson(1, 'Packing list', shared: true, tags: ['travel'], author: 'Tomas Rivera');

  group('logged out', () {
    testWidgets('opens on the shared notes with their authors, with one call that sends only the build-time key', (
      tester,
    ) async {
      final seen = await pumpApp(tester, server: FakeServer(shared: [sharedNote]).call);

      expect(find.text('Shared notes'), findsOneWidget);
      expect(find.text('Packing list'), findsOneWidget);
      expect(find.text('Shared by Tomas Rivera'), findsOneWidget);
      expect(requests(seen), ['GET /api/notes']);
      expect(seen.single.url.queryParameters['apikey'], 'build-key');
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });

    testWidgets('a shared note with no author says by Unknown', (tester) async {
      await pumpApp(tester, server: FakeServer(shared: [noteJson(1, 'Old note', shared: true, author: null)]).call);
      expect(find.text('Shared by Unknown'), findsOneWidget);
    });

    testWidgets('makes the demo account the main action, beside Create an account and Log in', (tester) async {
      await pumpApp(tester, server: FakeServer().call);

      expect(find.widgetWithText(FilledButton, 'Try the demo account'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Create an account'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsOneWidget);
      expect(find.byKey(const Key('demo-notice')), findsOneWidget);
      expect(
        find.text('This is a shared demo. Data resets every night. Do not use a real password or any private details.'),
        findsOneWidget,
      );
      expect(find.text('No shared notes yet.'), findsOneWidget);
    });

    testWidgets('offers no way to change a note', (tester) async {
      await pumpApp(tester, server: FakeServer(shared: [sharedNote]).call);

      for (final tooltip in ['Pin', 'Unpin', 'Share', 'Stop sharing', 'Edit', 'Delete']) {
        expect(find.byTooltip(tooltip), findsNothing);
      }
      expect(find.text('New note'), findsNothing);
    });

    testWidgets('search and tag filters work on the shared list, still with only the key', (tester) async {
      final server = FakeServer(
        shared: [sharedNote, noteJson(2, 'Git commands', shared: true, tags: ['code'])],
      );
      final seen = await pumpApp(tester, server: server.call);

      await search(tester, 'git');
      expect(seen.last.url.path, '/api/notes');
      expect(seen.last.url.queryParameters['q'], 'git');
      expect(seen.last.headers.containsKey('Authorization'), isFalse);
      expect(find.text('Git commands'), findsOneWidget);
      expect(find.text('Packing list'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'travel'));
      await tester.pumpAndSettle();
      expect(seen.last.url.queryParameters['tag'], 'travel');
      expect(seen.last.url.queryParameters.containsKey('q'), isFalse);
      expect(find.text('Packing list'), findsOneWidget);
      expect(find.text('Git commands'), findsNothing);
    });

    testWidgets('a bad key on the shared list says so, and Try again calls once more', (tester) async {
      final seen = await pumpApp(
        tester,
        server: (_) => json({
          'message':
              'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=notes',
        }, 401),
      );

      expect(find.text('The API key was not accepted.'), findsOneWidget);
      expect(find.textContaining('session has ended'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(seen.length, 2);
    });

    testWidgets('a list that does not load shows the rest of the page, and retries', (tester) async {
      var fail = true;
      final server = FakeServer(shared: [sharedNote]);
      await pumpApp(
        tester,
        server: (r) {
          if (!fail) return server.call(r);
          fail = false;
          return json({'message': 'Key service unavailable. Please try again shortly.'}, 503);
        },
      );

      expect(find.text('The service is busy. Please try again shortly.'), findsOneWidget);
      expect(find.text('Try the demo account'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Packing list'), findsOneWidget);
    });

    testWidgets('Load more adds the next page and hides once the list is complete', (tester) async {
      final seen = await pumpApp(
        tester,
        server: (r) {
          final next = r.url.queryParameters['page'] == '2';
          return json(
            page(
              // the second page repeats a row, as it can when a note is added between the two calls
              next ? [noteJson(2, 'Note two', shared: true), noteJson(3, 'Note three', shared: true)] : [noteJson(1, 'Note one', shared: true), noteJson(2, 'Note two', shared: true)],
              total: 4,
              page: next ? 2 : 1,
              perPage: 2,
            ),
          );
        },
      );

      expect(find.text('Note three'), findsNothing);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(seen.last.url.queryParameters['page'], '2');
      expect(find.text('Note one'), findsOneWidget);
      expect(find.text('Note two'), findsOneWidget);
      expect(find.text('Note three'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('a long body starts folded and opens', (tester) async {
      final body = List.generate(12, (i) => 'Line ${i + 1}').join('\n');
      await pumpApp(tester, server: FakeServer(shared: [noteJson(1, 'Long', body: body, shared: true)]).call);

      expect(tester.widget<Text>(find.text(body)).maxLines, 6);
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(body)).maxLines, isNull);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('a short body has nothing to open', (tester) async {
      await pumpApp(tester, server: FakeServer(shared: [sharedNote]).call);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('the back arrow opens the SimpleAPI home page, with a tooltip', (tester) async {
      await pumpApp(tester, server: FakeServer().call);

      expect(find.byTooltip('Back to SimpleAPI'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to SimpleAPI'));
      expect(opened, ['https://simpleapi.dev']);
    });
  });

  group('logging in', () {
    testWidgets('"Try the demo account" logs in as the demo user in one click and shows their notes', (tester) async {
      final server = FakeServer(shared: [sharedNote], notes: [noteJson(5, 'Start here')]);
      final seen = await pumpApp(tester, server: server.call);

      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();

      final login = seen.firstWhere((r) => r.url.path == '/api/users/login');
      expect(jsonDecode(login.body), {'email': 'demo@simpleapi.dev', 'password': 'try-the-demo'});
      expect(login.headers.containsKey('Authorization'), isFalse);
      expect(find.text('Start here'), findsOneWidget);
      expect(find.text('Packing list'), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Try the demo account'), findsNothing);
    });

    testWidgets('the log in screen also offers the demo account and shows the demo notice', (tester) async {
      await pumpApp(tester, server: FakeServer(notes: [noteJson(5, 'Start here')]).call);
      await tester.tap(appBarLogIn());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('demo-notice')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Try the demo account'));
      await tester.pumpAndSettle();

      expect(find.text('Start here'), findsOneWidget);
    });

    testWidgets('the log in form follows the shared login layout', (tester) async {
      await pumpApp(tester, server: FakeServer().call);
      await tester.tap(appBarLogIn());
      await tester.pumpAndSettle();
      await expectSharedLoginLayout(tester);
    });

    testWidgets('the Create an account button on the page opens the register form', (tester) async {
      await pumpApp(tester, server: FakeServer().call);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Create an account'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Register'), findsOneWidget);
      expect(find.byKey(const Key('demo-notice')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try the demo account'), findsOneWidget);
    });

    testWidgets('a failed demo login shows the API message', (tester) async {
      final server = FakeServer();
      await pumpApp(
        tester,
        server: (r) => r.url.path == '/api/users/login'
            ? json({'message': 'Invalid email or password.'}, 401)
            : server.call(r),
      );
      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid email or password.'), findsOneWidget);
    });

    testWidgets('register, then the empty list is shown; every call carries the key and the right user id', (
      tester,
    ) async {
      final seen = await pumpApp(tester, server: FakeServer().call);
      await logIn(tester, register: true);

      expect(find.text('Hi, Ann'), findsOneWidget);
      expect(find.text('No notes yet. Add your first one with New note.'), findsOneWidget);
      expect(requests(seen), ['GET /api/notes', 'POST /api/users/register', 'GET /api/users/42/notes']);
      expect(seen.every((r) => r.url.queryParameters['apikey'] == 'build-key'), isTrue);
      expect(seen.last.headers['Authorization'], 'Bearer tok');
    });

    testWidgets('a shared list that answers after the log in does not replace the user\'s notes', (tester) async {
      final late = Completer<http.Response>();
      final server = FakeServer(notes: [noteJson(5, 'My note')]);
      await pumpApp(
        tester,
        settle: false,
        server: (r) => r.url.path == '/api/notes' ? late.future : server.call(r),
      );

      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();
      expect(find.text('My note'), findsOneWidget);

      late.complete(json(page([sharedNote])));
      await tester.pumpAndSettle();
      expect(find.text('My note'), findsOneWidget);
      expect(find.text('Packing list'), findsNothing);
    });

    testWidgets('a failed login (401) shows the API message and is not an expired session', (tester) async {
      await pumpApp(
        tester,
        server: (r) => r.url.path == '/api/notes' ? json(page([])) : json({'message': 'Invalid email or password.'}, 401),
      );
      await logIn(tester);

      expect(find.text('Invalid email or password.'), findsOneWidget);
      expect(find.textContaining('session has ended'), findsNothing);
      expect(find.textContaining('API key'), findsNothing);
      expect(find.text('Hi, Ann'), findsNothing);
      // still on the login form, so the user can try again
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    });

    testWidgets('a 401 about the key on the login form is explained as a key problem', (tester) async {
      await pumpApp(
        tester,
        server: (r) => r.url.path == '/api/notes'
            ? json(page([]))
            : json({
                'message':
                    'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=notes',
              }, 401),
      );
      await logIn(tester);

      expect(find.textContaining('The API key was not accepted'), findsOneWidget);
    });

    /// Answers every login or register with [answer]; the list still works.
    FutureOr<http.Response> Function(http.Request) refuse(http.Response answer) =>
        (r) => r.url.path == '/api/notes' ? json(page([])) : answer;

    testWidgets('register shows the validation text for a short password (422)', (tester) async {
      await pumpApp(tester, server: refuse(json({'message': 'The password must be at least 8 characters.'}, 422)));
      await logIn(tester, register: true);

      expect(find.text('The password must be at least 8 characters.'), findsOneWidget);
    });

    testWidgets('registering an email twice shows the API message (409)', (tester) async {
      await pumpApp(tester, server: refuse(json({'message': 'That email is already registered to this key.'}, 409)));
      await logIn(tester, register: true);

      expect(find.textContaining('already registered'), findsOneWidget);
    });

    testWidgets('409 (key uses an external auth service) is shown as a conflict', (tester) async {
      await pumpApp(tester, server: refuse(json({'message': 'This key uses an external auth service.'}, 409)));
      await logIn(tester, register: true);

      expect(find.text('This key uses an external auth service.'), findsOneWidget);
    });

    testWidgets('a full demo key (403 on register) shows the demo-full message', (tester) async {
      await pumpApp(tester, server: refuse(json({'message': 'Free tier limit reached: 25 users per key.'}, 403)));
      await logIn(tester, register: true);

      expect(find.text('The demo is full. It resets every night.'), findsOneWidget);
    });

    testWidgets('a malformed JSON body (400) shows the API message', (tester) async {
      await pumpApp(tester, server: refuse(json({'message': 'Malformed JSON body. Send a valid JSON object.'}, 400)));
      await logIn(tester, register: true);

      expect(find.text('Malformed JSON body. Send a valid JSON object.'), findsOneWidget);
    });

    testWidgets('503 says the service is busy', (tester) async {
      await pumpApp(tester, server: refuse(json({'message': 'Key service unavailable. Please try again shortly.'}, 503)));
      await logIn(tester);

      expect(find.text('The service is busy. Please try again shortly.'), findsOneWidget);
    });

    testWidgets('429 asks the user to wait', (tester) async {
      await pumpApp(
        tester,
        server: refuse(json({'message': 'Rate limit exceeded: 60 requests a minute per IP address.'}, 429)),
      );
      await logIn(tester);

      expect(find.text('Too many requests. Wait a few seconds and try again.'), findsOneWidget);
    });
  });

  group('your notes', () {
    testWidgets('pinned notes come first, and every note shows its text and tags', (tester) async {
      final server = FakeServer(
        notes: [
          noteJson(1, 'Older pinned', pinned: true),
          noteJson(2, 'Newest plain', body: 'Plain text', tags: ['home', 'work']),
        ],
      );
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      expect(seen.last.url.path, '/api/users/42/notes');
      expect(tester.getTopLeft(find.text('Older pinned')).dy, lessThan(tester.getTopLeft(find.text('Newest plain')).dy));
      expect(find.text('Plain text'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'home'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'work'), findsOneWidget);
      expect(onCard('Older pinned', 'Unpin'), findsOneWidget);
      expect(onCard('Newest plain', 'Pin'), findsOneWidget);
    });

    testWidgets('only a shared note shows its author', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Open', shared: true), noteJson(2, 'Private')]);
      await pumpApp(tester, server: server.call);
      await logIn(tester);

      expect(find.text('Shared by Ann'), findsOneWidget);
      expect(onCard('Open', 'Stop sharing'), findsOneWidget);
      expect(onCard('Private', 'Share'), findsOneWidget);
    });

    testWidgets('add a note with every field', (tester) async {
      final server = FakeServer();
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), ' Trip plan ');
      await tester.enterText(find.widgetWithText(TextField, 'Body'), 'Train at nine');
      await tester.enterText(find.widgetWithText(TextField, 'Tags'), 'Travel, , home ,');
      await tester.tap(find.widgetWithText(SwitchListTile, 'Pinned'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Shared'));
      await tester.pump();
      await saveDialog(tester);

      final post = seen.firstWhere((r) => r.method == 'POST' && r.url.path == '/api/users/42/notes');
      expect(bodyOf(post), {
        'title': 'Trip plan',
        'body': 'Train at nine',
        'tags': ['travel', 'home'],
        'pinned': true,
        'shared': true,
      });
      expect(requests(seen).last, 'GET /api/users/42/notes');
      expect(find.text('Trip plan'), findsOneWidget);
      expect(find.text('Shared by Ann'), findsOneWidget);
      expect(onCard('Trip plan', 'Unpin'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('a note needs a title: Save stays off and nothing is sent', (tester) async {
      final seen = await pumpApp(tester, server: FakeServer().call);
      await logIn(tester);
      final before = seen.length;

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), '   ');
      await tester.pump();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
      expect(seen.length, before);
    });

    testWidgets('a new note clears the filters, so it shows', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Bike log')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);
      await search(tester, 'bike');

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Groceries');
      await saveDialog(tester);

      expect(seen.last.url.queryParameters.containsKey('q'), isFalse);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Bike log'), findsOneWidget);
    });

    testWidgets('pin and unpin send only pinned, and a pinned note moves to the top', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Oldest'), noteJson(2, 'Newest')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);
      expect(tester.getTopLeft(find.text('Newest')).dy, lessThan(tester.getTopLeft(find.text('Oldest')).dy));

      await tester.tap(onCard('Oldest', 'Pin'));
      await tester.pumpAndSettle();
      final put = seen.firstWhere((r) => r.method == 'PUT');
      expect(put.url.path, '/api/users/42/notes/1');
      expect(bodyOf(put), {'pinned': true});
      expect(tester.getTopLeft(find.text('Oldest')).dy, lessThan(tester.getTopLeft(find.text('Newest')).dy));

      await tester.tap(onCard('Oldest', 'Unpin'));
      await tester.pumpAndSettle();
      expect(bodyOf(seen.lastWhere((r) => r.method == 'PUT')), {'pinned': false});
      expect(tester.getTopLeft(find.text('Newest')).dy, lessThan(tester.getTopLeft(find.text('Oldest')).dy));
    });

    testWidgets('share and stop sharing send only shared', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Plan')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(onCard('Plan', 'Share'));
      await tester.pumpAndSettle();
      expect(bodyOf(seen.lastWhere((r) => r.method == 'PUT')), {'shared': true});
      expect(find.text('Shared by Ann'), findsOneWidget);

      await tester.tap(onCard('Plan', 'Stop sharing'));
      await tester.pumpAndSettle();
      expect(bodyOf(seen.lastWhere((r) => r.method == 'PUT')), {'shared': false});
      expect(find.text('Shared by Ann'), findsNothing);
    });

    testWidgets('edit sends only what changed', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Plan', tags: ['work'])]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit note'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Better plan');
      await saveDialog(tester);

      final put = seen.lastWhere((r) => r.method == 'PUT');
      expect(put.url.path, '/api/users/42/notes/1');
      expect(bodyOf(put), {'title': 'Better plan'});
      expect(find.text('Better plan'), findsOneWidget);
    });

    testWidgets('edit can clear the tags and the body: empty values are sent', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Plan', body: 'Text', tags: ['work', 'home'])]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Tags')).controller?.text, 'work, home');
      await tester.enterText(find.widgetWithText(TextField, 'Tags'), '');
      await tester.enterText(find.widgetWithText(TextField, 'Body'), '');
      await saveDialog(tester);

      expect(bodyOf(seen.lastWhere((r) => r.method == 'PUT')), {'tags': [], 'body': ''});
      expect(find.widgetWithText(ActionChip, 'work'), findsNothing);
    });

    testWidgets('edit with no change sends nothing', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Plan', tags: ['work'])]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await saveDialog(tester);

      expect(seen.where((r) => r.method == 'PUT'), isEmpty);
      expect(find.text('Edit note'), findsNothing);
    });

    testWidgets('delete asks first, and Cancel keeps the note', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Plan')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(seen.where((r) => r.method == 'DELETE'), isEmpty);
      expect(find.text('Plan'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      final delete = seen.lastWhere((r) => r.method == 'DELETE');
      expect(delete.url.path, '/api/users/42/notes/1');
      expect(find.text('Plan'), findsNothing);
      expect(find.text('No notes yet. Add your first one with New note.'), findsOneWidget);
    });

    testWidgets('search waits for a pause in typing, then sends q once', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Bike log'), noteJson(2, 'Recipes', body: 'Soup')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);
      final before = seen.length;

      await tester.enterText(find.widgetWithText(TextField, 'Search notes'), 'b');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.widgetWithText(TextField, 'Search notes'), 'bi');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.widgetWithText(TextField, 'Search notes'), 'bike');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(seen.length, before + 1);
      expect(seen.last.url.path, '/api/users/42/notes');
      expect(seen.last.url.queryParameters['q'], 'bike');
      expect(find.text('Bike log'), findsOneWidget);
      expect(find.text('Recipes'), findsNothing);
    });

    testWidgets('pressing Enter in the search box searches at once', (tester) async {
      final server = FakeServer(notes: [noteJson(1, 'Bike log')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Search notes'), 'bike');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(seen.last.url.queryParameters['q'], 'bike');
    });

    testWidgets('an older search that answers late does not replace a newer one', (tester) async {
      final slow = Completer<http.Response>();
      final server = FakeServer(notes: [noteJson(1, 'Bike log'), noteJson(2, 'Recipes')]);
      await pumpApp(
        tester,
        server: (r) => r.url.queryParameters['q'] == 'old' ? slow.future : server.call(r),
      );
      await logIn(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Search notes'), 'old');
      await tester.pump(const Duration(milliseconds: 400)); // still waiting for this answer
      await search(tester, 'recipes');
      expect(find.text('Recipes'), findsOneWidget);

      slow.complete(json(page([noteJson(1, 'Bike log')])));
      await tester.pumpAndSettle();
      expect(find.text('Recipes'), findsOneWidget);
      expect(find.text('Bike log'), findsNothing);
    });

    testWidgets('a search that finds nothing says so', (tester) async {
      await pumpApp(tester, server: FakeServer(notes: [noteJson(1, 'Bike log')]).call);
      await logIn(tester);

      await search(tester, 'zebra');
      expect(find.text('No notes match.'), findsOneWidget);
    });

    testWidgets('filter by tag from the chips or from a note, and pick it again to clear it', (tester) async {
      final server = FakeServer(
        notes: [
          noteJson(1, 'Plan', tags: ['work']),
          noteJson(2, 'Recipes', tags: ['food']),
        ],
      );
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'food'));
      await tester.pumpAndSettle();
      expect(seen.last.url.queryParameters['tag'], 'food');
      expect(find.text('Plan'), findsNothing);
      // the other tag stays on offer, so the filter can be changed
      expect(find.widgetWithText(FilterChip, 'work'), findsOneWidget);
      expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'food')).selected, isTrue);

      await tester.tap(find.widgetWithText(FilterChip, 'food'));
      await tester.pumpAndSettle();
      expect(seen.last.url.queryParameters.containsKey('tag'), isFalse);
      expect(find.text('Plan'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'work'));
      await tester.pumpAndSettle();
      expect(seen.last.url.queryParameters['tag'], 'work');
      expect(find.text('Recipes'), findsNothing);
    });

    testWidgets('a filter stays on while notes change', (tester) async {
      final server = FakeServer(
        notes: [
          noteJson(1, 'Plan', tags: ['work']),
          noteJson(2, 'Recipes', tags: ['food']),
        ],
      );
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'work'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();

      expect(seen.last.method, 'GET');
      expect(seen.last.url.queryParameters['tag'], 'work');
      expect(find.text('Recipes'), findsNothing);
    });

    testWidgets('logging in and out starts with no filter', (tester) async {
      final server = FakeServer(shared: [sharedNote], notes: [noteJson(5, 'My note', tags: ['mine'])]);
      final seen = await pumpApp(tester, server: server.call);

      await search(tester, 'pack');
      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();
      expect(seen.last.url.path, '/api/users/42/notes');
      expect(seen.last.url.queryParameters.containsKey('q'), isFalse);
      expect(find.text('My note'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(seen.last.url.path, '/api/notes');
      expect(seen.last.url.queryParameters.containsKey('tag'), isFalse);
      expect(find.widgetWithText(FilterChip, 'mine'), findsNothing);
    });

    testWidgets('log out posts to the API and shows the shared notes with only the key', (tester) async {
      final server = FakeServer(shared: [sharedNote], notes: [noteJson(5, 'My note')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(requests(seen).skip(seen.length - 2), ['POST /api/users/logout', 'GET /api/notes']);
      expect(seen.last.headers.containsKey('Authorization'), isFalse);
      expect(find.text('My note'), findsNothing);
      expect(find.text('Packing list'), findsOneWidget);
      expect(find.text('Shared notes'), findsOneWidget);
    });

    testWidgets('the demo account is never offered a way to change or delete itself', (tester) async {
      await pumpApp(tester, server: FakeServer(notes: [noteJson(5, 'My note')]).call);
      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();

      expect(find.textContaining('account'), findsNothing);
      expect(find.textContaining('password'), findsNothing);
    });
  });

  group('errors on your notes', () {
    Future<(FakeServer, List<http.Request>)> loggedIn(WidgetTester tester) async {
      final server = FakeServer(shared: [sharedNote], notes: [noteJson(1, 'Plan')]);
      final seen = await pumpApp(tester, server: server.call);
      await logIn(tester);
      return (server, seen);
    }

    testWidgets('login and register never send the bearer token, even after a session ended', (tester) async {
      final (server, seen) = await loggedIn(tester);
      server.failNext = json({'message': 'Invalid or expired auth token. Log in again.'}, 401);
      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();
      expect(appBarLogIn(), findsOneWidget);

      seen.clear();
      await logIn(tester);
      expect(seen.where((r) => r.url.path == '/api/users/login').single.headers.containsKey('Authorization'), isFalse);
    });

    testWidgets('a user_id that is not yours (403) shows the message and keeps you logged in', (tester) async {
      final (server, _) = await loggedIn(tester);

      server.failNext = json({'message': 'The user_id in the path is not the user of this token.'}, 403);
      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not the user of this token'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('the 100-note limit (403) shows the API message and keeps the typed text', (tester) async {
      final (server, _) = await loggedIn(tester);

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'One too many');
      server.failNext = json({'message': 'Free tier limit reached: 100 notes per user.'}, 403);
      await saveDialog(tester);

      expect(find.text('Free tier limit reached: 100 notes per user.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'One too many'), findsOneWidget); // the form stays open
      expect(find.text('Plan'), findsOneWidget);
    });

    testWidgets('a validation error (422) on edit shows the API message and keeps the form', (tester) async {
      final (server, _) = await loggedIn(tester);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Tags'), 'x' * 31);
      server.failNext = json({'message': 'The tags.0 must not be greater than 30 characters.'}, 422);
      await saveDialog(tester);

      expect(find.text('The tags.0 must not be greater than 30 characters.'), findsOneWidget);
      expect(find.text('Edit note'), findsOneWidget);
    });

    testWidgets('a form that failed can be sent again', (tester) async {
      final (server, _) = await loggedIn(tester);

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Second try');
      server.failNext = json({'message': 'Key service unavailable. Please try again shortly.'}, 503);
      await saveDialog(tester);
      expect(find.text('The service is busy. Please try again shortly.'), findsOneWidget);

      await saveDialog(tester);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Second try'), findsOneWidget);
    });

    testWidgets('a note that is already gone (404) is explained and leaves the list', (tester) async {
      final (server, _) = await loggedIn(tester);

      server.notes.clear(); // deleted in another tab
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not found. It may already have been deleted.'), findsOneWidget);
      expect(find.text('Plan'), findsNothing);
    });

    testWidgets('a dead token on a write (401) logs the user out and shows the shared notes', (tester) async {
      final (server, _) = await loggedIn(tester);

      server.failNext = json({'message': 'Invalid or expired auth token. Log in again.'}, 401);
      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();

      expect(find.text('Your session has ended. Please log in again.'), findsOneWidget);
      expect(find.text('Shared notes'), findsOneWidget);
      expect(find.text('Packing list'), findsOneWidget);
      expect(find.text('Plan'), findsNothing);
      expect(appBarLogIn(), findsOneWidget);
    });

    testWidgets('a dead token on a search (401) does the same', (tester) async {
      final (server, _) = await loggedIn(tester);

      server.failNext = json({'message': 'Invalid or expired auth token. Log in again.'}, 401);
      await search(tester, 'plan');

      expect(find.text('Your session has ended. Please log in again.'), findsOneWidget);
      expect(find.text('Packing list'), findsOneWidget);
    });

    testWidgets('a dead token in the form (401) closes it and logs the user out', (tester) async {
      final (server, _) = await loggedIn(tester);

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Too late');
      server.failNext = json({'message': 'Invalid or expired auth token. Log in again.'}, 401);
      await saveDialog(tester);

      expect(find.text('Your session has ended. Please log in again.'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Packing list'), findsOneWidget);
    });

    testWidgets('a list that fails to reload keeps the notes on screen and says why', (tester) async {
      final (server, _) = await loggedIn(tester);

      server.failNextList = json({'message': 'Key service unavailable. Please try again shortly.'}, 503);
      await tester.tap(onCard('Plan', 'Pin'));
      await tester.pumpAndSettle();

      expect(find.text('The service is busy. Please try again shortly.'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
    });
  });

  group('at 360px wide', () {
    final longNote = noteJson(
      1,
      'A long title that has to wrap on a phone, because nobody cut it short before saving the note',
      body: 'A long line of text ' * 30,
      shared: true,
      tags: ['travel', 'checklist', 'work', 'home', 'reference'],
      author: 'Someone With A Rather Long Name',
    );

    testWidgets('the app bar shows the full title and fits its actions, logged out and in', (tester) async {
      await pumpApp(tester, server: FakeServer().call);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();

      // The test font is about twice as wide as Roboto, so this checks the layout (no overflow, nothing cut
      // off) rather than exact widths. In Roboto the title is about 137px and leaves room for the actions.
      expect(find.text('SimpleAPI Notes'), findsOneWidget);
      expect(appBarLogIn(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();
      expect(find.text('SimpleAPI Notes'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long note fits on the shared list', (tester) async {
      await pumpApp(tester, server: FakeServer(shared: [longNote]).call);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byType(Card), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(Card)).right, lessThanOrEqualTo(360));
    });

    testWidgets('a long note and its buttons fit on your own list', (tester) async {
      final server = FakeServer(notes: [longNote]);
      await pumpApp(tester, server: server.call);
      await logIn(tester);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byTooltip('Delete'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final tooltip in ['Pin', 'Stop sharing', 'Edit', 'Delete']) {
        final box = tester.getRect(find.byTooltip(tooltip));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(360));
      }
    });

    testWidgets('the note form fits and Save can be reached', (tester) async {
      await pumpApp(tester, server: FakeServer().call);
      await logIn(tester);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      expect(save.right, lessThanOrEqualTo(360));
      expect(save.bottom, lessThanOrEqualTo(640));
      expect(tester.getSize(find.widgetWithText(TextField, 'Title')).width, greaterThan(250));
    });
  });

  group('forgot password', () {
    /// Answers the forgot and reset calls; the list still works.
    http.Response Function(http.Request) resetServer(http.Response resetAnswer) =>
        (r) {
          if (r.url.path == '/api/notes') return json(page([]));
          if (r.url.path == '/api/users/forgot') {
            return json({'message': 'If an account exists for that email, a reset code has been sent.'});
          }
          return resetAnswer;
        };

    testWidgets('request a code, then reset with it', (tester) async {
      final seen = await pumpApp(tester, server: resetServer(json({'message': 'Password updated. Please log in.'})));
      await tester.tap(appBarLogIn());
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Set new password'), findsNothing); // step 2 appears after step 1
      await tester.tap(find.text('Email me a code'));
      await tester.pumpAndSettle();
      expect(seen.last.url.path, '/api/users/forgot');
      expect(jsonDecode(seen.last.body), {'email': 'ann@example.com'});
      expect(find.textContaining('If an account exists'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '123456');
      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'new-password');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();
      expect(seen.last.url.path, '/api/users/reset');
      expect(jsonDecode(seen.last.body), {'email': 'ann@example.com', 'code': '123456', 'password': 'new-password'});
      expect(find.textContaining('Password updated. Please log in.'), findsOneWidget);
    });

    testWidgets('a reset refused for the demo account (403) shows the API message', (tester) async {
      await pumpApp(
        tester,
        server: (r) => r.url.path == '/api/notes'
            ? json(page([]))
            : json({'message': 'The demo account cannot be changed.'}, 403),
      );
      await tester.tap(appBarLogIn());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'demo@simpleapi.dev');
      await tester.tap(find.text('Email me a code'));
      await tester.pumpAndSettle();

      expect(find.text('The demo account cannot be changed.'), findsOneWidget);
      expect(find.text('Set new password'), findsNothing);
    });

    testWidgets('a wrong reset code (400) is shown and the form stays', (tester) async {
      await pumpApp(tester, server: resetServer(json({'message': 'Invalid or expired reset code.'}, 400)));
      await tester.tap(appBarLogIn());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
      await tester.tap(find.text('Email me a code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '000000');
      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'new-password');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid or expired reset code.'), findsOneWidget);
      expect(find.text('Set new password'), findsOneWidget);
    });
  });
}
