/// The small data types shared by the API client and the screens.
library;

/// Thrown for any non-2xx answer. [message] is the API's own text,
/// e.g. "Invalid email or password."
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class Note {
  const Note({
    required this.id,
    required this.title,
    this.body = '',
    this.pinned = false,
    this.shared = false,
    this.tags = const [],
    this.author,
  });

  final int id;
  final String title;
  final String body;
  final bool pinned;
  final bool shared;
  final List<String> tags;

  /// The name of the user who wrote it, or null if there is none.
  final String? author;

  /// `pinned` and `shared` are real booleans on every route, and `body` may be null.
  factory Note.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return Note(
      id: (json['id'] as num).toInt(),
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      pinned: json['pinned'] == true,
      shared: json['shared'] == true,
      tags: [for (final tag in (json['tags'] as List? ?? const [])) '$tag'],
      author: author is String && author.trim().isNotEmpty ? author : null,
    );
  }
}

/// One page of a list. Every list answers `{data, total, page, per_page}`.
class NotePage {
  const NotePage({required this.notes, required this.total, required this.page, required this.perPage});

  final List<Note> notes;
  final int total;
  final int page;
  final int perPage;

  bool get hasMore => page * perPage < total;

  factory NotePage.fromJson(Map<String, dynamic> json) {
    return NotePage(
      notes: [for (final n in (json['data'] as List? ?? const [])) Note.fromJson(n as Map<String, dynamic>)],
      total: (json['total'] as num? ?? 0).toInt(),
      page: (json['page'] as num? ?? 1).toInt(),
      perPage: (json['per_page'] as num? ?? 25).toInt(),
    );
  }
}

/// What login / register answer with. [token] is null only for a 2xx answer
/// that carried no token.
class AuthResult {
  const AuthResult({this.token, this.id, this.name = '', this.message = ''});

  final String? token;
  final int? id;
  final String name;
  final String message;
}
