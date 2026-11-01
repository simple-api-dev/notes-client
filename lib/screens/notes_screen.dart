/// The notes screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../notes_api.dart';
import '../open_url.dart';
import 'auth_screen.dart';
import 'note_dialog.dart';
import 'ui.dart';

/// The landing screen. Logged out it shows the shared notes, which need only
/// the API key, and offers to log in or register. Logged in it lists the user's
/// own notes, and adds, edits, deletes, pins, shares and tags them. Both lists
/// can be searched and filtered by tag.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  /// How long typing has to pause before a search goes out: the API allows 60 requests a minute.
  static const _searchPause = Duration(milliseconds: 400);

  final _search = TextEditingController();
  Timer? _searchTimer;
  String? _tag;

  /// The tags offered as filters: every tag seen in the list. The API has no list of tags.
  Set<String> _tags = {};

  List<Note> _notes = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  bool _wasLoggedIn = false;

  /// Numbers the loads. Only the answer to the latest one counts: an older answer
  /// may be for another search, or for the list from before a log in.
  int _latestLoad = 0;

  AppState get state => widget.state;

  bool get _filtered => _search.text.trim().isNotEmpty || _tag != null;

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
    _wasLoggedIn = state.loggedIn;
    _reload();
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Logging in shows the user's notes and logging out the shared ones, each
  /// starting with no filter.
  void _onStateChanged() {
    if (state.loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = state.loggedIn;
    _clearFilters();
    _tags = {};
    _reload();
  }

  void _clearFilters() {
    _searchTimer?.cancel();
    _search.clear();
    _tag = null;
  }

  /// Forgets the list on screen and loads the first page.
  void _reload() {
    _notes = [];
    _hasMore = false;
    _error = null;
    _loading = true;
    _load();
  }

  // GET /api/notes  or  GET /api/users/{user_id}/notes
  Future<void> _load({int page = 1}) async {
    final load = ++_latestLoad;
    final own = state.loggedIn;
    final text = _search.text.trim();
    final q = text.isEmpty ? null : text;
    final tag = _tag;
    try {
      final result = own
          ? await state.api.listNotes(q: q, tag: tag, page: page)
          : await state.api.listSharedNotes(q: q, tag: tag, page: page);
      if (load != _latestLoad || !mounted) return;
      final found = result.notes.expand((note) => note.tags);
      setState(() {
        // A note added meanwhile shifts the pages, so the next page can repeat a row.
        final shown = {if (page > 1) ..._notes.map((note) => note.id)};
        _notes = [
          if (page > 1) ..._notes,
          for (final note in result.notes)
            if (shown.add(note.id)) note,
        ];
        _tags = page == 1 && q == null && tag == null ? found.toSet() : {..._tags, ...found};
        _page = result.page;
        _hasMore = result.hasMore;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (load != _latestLoad || !mounted) return;
      // a 401 while logged in means the session is over, and the shared notes load next
      if (own && e is ApiException && e.statusCode == 401) {
        showSnack(context, describeError(e));
        state.sessionExpired();
        return;
      }
      setState(() {
        _loading = false;
        _error = _notes.isEmpty ? e : null;
      });
      if (_notes.isNotEmpty) showSnack(context, describeError(e));
    }
  }

  void _loadMore() {
    setState(() => _loading = true);
    _load(page: _page + 1);
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchPause, _applyFilters);
    setState(() {}); // shows or hides the clear button
  }

  void _applyFilters() {
    _searchTimer?.cancel();
    setState(_reload);
  }

  void _clearSearch() {
    _search.clear();
    _applyFilters();
  }

  /// Picking the tag that is already the filter removes the filter.
  void _filterByTag(String tag) {
    _tag = _tag == tag ? null : tag;
    _applyFilters();
  }

  /// Runs one write, then loads the list again, so the order and the filters
  /// stay right. Shows a readable error if it fails, and logs the user out
  /// locally if the API says the token is no longer valid.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) state.sessionExpired();
      if (mounted) showSnack(context, describeError(e));
      // a 404 means the list on screen is out of date
      if (e is ApiException && e.statusCode == 404) await _load();
    }
  }

  // PUT /api/users/{user_id}/notes/{id}  (pinned)
  Future<void> _togglePin(Note n) => _run(() => state.api.updateNote(n.id, pinned: !n.pinned));

  // PUT /api/users/{user_id}/notes/{id}  (shared)
  Future<void> _toggleShare(Note n) => _run(() => state.api.updateNote(n.id, shared: !n.shared));

  /// The dialog makes the POST or PUT itself, so a refused note stays open with its text.
  Future<void> _edit([Note? note]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => NoteDialog(state: state, note: note),
    );
    if (saved != true || !mounted) return;
    if (note == null) _clearFilters(); // a new note might not match them, and it should show
    await _load();
  }

  // DELETE /api/users/{user_id}/notes/{id}
  Future<void> _delete(Note n) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text(n.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure == true) await _run(() => state.api.deleteNote(n.id));
  }

  // POST /api/users/login as the shared demo user
  Future<void> _demo() async {
    try {
      await state.loginDemo();
    } catch (e) {
      if (mounted) showSnack(context, describeLoginError(e));
    }
  }

  void _openAuth({bool register = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AuthScreen(state: state, startAsRegister: register),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: BackToSimpleApi(openUrl: widget.openUrl),
          title: const Text('SimpleAPI Notes'),
          actions: [
            if (state.loggedIn) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width < 480 ? 64 : 200),
                child: Center(child: Text('Hi, ${state.userName ?? 'you'}', overflow: TextOverflow.ellipsis)),
              ),
              TextButton(
                onPressed: state.logout,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Log out'),
              ),
            ] else
              TextButton(
                onPressed: _openAuth,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Log in'),
              ),
          ],
        ),
        floatingActionButton: state.loggedIn
            ? FloatingActionButton.extended(
                onPressed: _edit,
                icon: const Icon(Icons.add),
                label: const Text('New note'),
              )
            : null,
        body: Centered(child: _body()),
      ),
    );
  }

  /// One scrolling list, so nothing is squeezed on a phone: the header goes up with the notes.
  Widget _body() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 88), // room for the New note button
      children: [
        if (!state.loggedIn)
          _LoggedOutHeader(onDemo: _demo, onLogin: _openAuth, onRegister: () => _openAuth(register: true)),
        _filters(),
        ..._list(),
      ],
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search notes',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.clear), onPressed: _clearSearch),
            ),
            onChanged: _searchChanged,
            onSubmitted: (_) => _applyFilters(),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in _tags.toList()..sort())
                  FilterChip(label: Text(tag), selected: tag == _tag, onSelected: (_) => _filterByTag(tag)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _list() {
    if (_notes.isEmpty && _loading) {
      return const [
        Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      ];
    }
    final error = _error;
    if (error != null) return [ErrorView(error: error, onRetry: () => setState(_reload))];
    if (_notes.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _filtered
                ? 'No notes match.'
                : state.loggedIn
                ? 'No notes yet. Add your first one with New note.'
                : 'No shared notes yet.',
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      for (final n in _notes)
        _NoteCard(
          key: ValueKey(n.id),
          note: n,
          onTag: _filterByTag,
          actions: state.loggedIn ? _actions(n) : null,
        ),
      if (_hasMore)
        Center(
          child: OutlinedButton(onPressed: _loading ? null : _loadMore, child: const Text('Load more')),
        ),
    ];
  }

  Widget _actions(Note n) {
    final on = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: n.pinned ? 'Unpin' : 'Pin',
          icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined, color: n.pinned ? on : null),
          onPressed: () => _togglePin(n),
        ),
        IconButton(
          tooltip: n.shared ? 'Stop sharing' : 'Share',
          icon: Icon(n.shared ? Icons.people : Icons.people_outline, color: n.shared ? on : null),
          onPressed: () => _toggleShare(n),
        ),
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(n)),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(n)),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({super.key, required this.note, required this.onTag, this.actions});

  final Note note;
  final ValueChanged<String> onTag;

  /// The owner's buttons. Null on the shared list, which is read-only.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.title, style: text.titleMedium),
            if (note.shared) Text('Shared ${byAuthor(note.author)}', style: text.bodySmall),
            if (note.body.isNotEmpty) ...[const SizedBox(height: 8), _NoteBody(note.body)],
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final tag in note.tags)
                    ActionChip(
                      label: Text(tag),
                      tooltip: 'Filter by $tag',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onTag(tag),
                    ),
                ],
              ),
            ],
            ?actions,
          ],
        ),
      ),
    );
  }
}

/// A body holds up to 10000 characters: a long one starts folded.
class _NoteBody extends StatefulWidget {
  const _NoteBody(this.text);

  final String text;

  @override
  State<_NoteBody> createState() => _NoteBodyState();
}

class _NoteBodyState extends State<_NoteBody> {
  static const _foldedLines = 6;

  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final style = DefaultTextStyle.of(context).style;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _foldedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _open ? null : _foldedLines,
              overflow: _open ? null : TextOverflow.ellipsis,
            ),
            if (long)
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                child: Text(_open ? 'Show less' : 'Show more'),
              ),
          ],
        );
      },
    );
  }
}

class _LoggedOutHeader extends StatelessWidget {
  const _LoggedOutHeader({required this.onDemo, required this.onLogin, required this.onRegister});

  final VoidCallback onDemo;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        children: [
          const Text('Shared notes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'This sample talks to the free SimpleAPI Notes API. The notes below are shared, so they need only the API '
            'key. To write your own, try the shared demo account in one click, or create an account with any email '
            'address. It is not verified.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onDemo, child: const Text('Try the demo account')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: onRegister, child: const Text('Create an account')),
              OutlinedButton(onPressed: onLogin, child: const Text('Log in')),
            ],
          ),
          const SizedBox(height: 16),
          const Text(demoNoticeText, key: Key('demo-notice'), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
