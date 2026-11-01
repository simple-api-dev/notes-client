/// The form for a new note or an edit.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../notes_api.dart';
import 'ui.dart';

/// Adds a note, or edits [note]. It stays open until the save worked, so a
/// refused note keeps its text and shows the API's message. Pops `true` when
/// something was saved.
class NoteDialog extends StatefulWidget {
  const NoteDialog({super.key, required this.state, this.note});

  final AppState state;
  final Note? note;

  @override
  State<NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<NoteDialog> {
  late final _title = TextEditingController(text: widget.note?.title);
  late final _body = TextEditingController(text: widget.note?.body);
  late final _tags = TextEditingController(text: widget.note?.tags.join(', '));
  late bool _pinned = widget.note?.pinned ?? false;
  late bool _shared = widget.note?.shared ?? false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  List<String> _typedTags() =>
      _tags.text.split(',').map((tag) => tag.trim().toLowerCase()).where((tag) => tag.isNotEmpty).toList();

  // POST /api/users/{user_id}/notes
  Future<void> _create() async {
    final body = _body.text.trim();
    await widget.state.api.createNote(
      title: _title.text.trim(),
      body: body.isEmpty ? null : body,
      tags: _typedTags(),
      pinned: _pinned,
      shared: _shared,
    );
  }

  // PUT /api/users/{user_id}/notes/{id}  (only the fields that changed)
  Future<bool> _update(Note note) async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    final tags = _typedTags();
    final sameTags = listEquals(tags, note.tags);
    final sameBody = body == note.body.trim();
    if (title == note.title && sameBody && sameTags && _pinned == note.pinned && _shared == note.shared) return false;
    await widget.state.api.updateNote(
      note.id,
      title: title == note.title ? null : title,
      body: sameBody ? null : body,
      tags: sameTags ? null : tags,
      pinned: _pinned == note.pinned ? null : _pinned,
      shared: _shared == note.shared ? null : _shared,
    );
    return true;
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = widget.note;
      var saved = true;
      if (note == null) {
        await _create();
      } else {
        saved = await _update(note);
      }
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 401) {
        // the session is over: there is nothing left to save to
        showSnack(context, describeError(e));
        Navigator.pop(context);
        widget.state.sessionExpired();
        return;
      }
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrolls, so the buttons stay reachable above a phone keyboard.
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: Text(widget.note == null ? 'New note' : 'Edit note'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Body',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags',
                helperText: 'Separate tags with commas',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pinned'),
              value: _pinned,
              onChanged: (value) => setState(() => _pinned = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shared'),
              subtitle: const Text('Anyone with the API key can read a shared note.'),
              value: _shared,
              onChanged: (value) => setState(() => _shared = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy || _title.text.trim().isEmpty ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
