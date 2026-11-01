/// Small shared widgets and the error wording.
library;

import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../open_url.dart';

/// The same wording as the other SimpleAPI samples. 400, 403, 409 and 422 show
/// the API's own message, which is already a clear sentence.
String describeError(Object e) {
  if (e is! ApiException) return 'Something went wrong. Please try again.';
  switch (e.statusCode) {
    case 401:
      return isTokenProblem(e)
          ? 'Your session has ended. Please log in again.'
          : 'The API key was not accepted.';
    case 400:
    case 403:
    case 409:
    case 422:
      return e.message;
    case 404:
      return 'Not found. It may already have been deleted.';
    case 429:
      return 'Too many requests. Wait a few seconds and try again.';
    case 503:
      return 'The service is busy. Please try again shortly.';
    default:
      return e.message;
  }
}

/// Like [describeError], for the login form. A failed login is a 401 too
/// ("Invalid email or password."): it is shown as it is, and it is not an
/// expired session (nobody is logged in yet). Only a 401 about the key is
/// explained as a key problem.
String describeLoginError(Object e) =>
    e is ApiException && e.statusCode == 401 && !isKeyProblem(e) ? e.message : describeError(e);

/// True for a 401 about the apikey (as opposed to the token or a login).
bool isKeyProblem(ApiException e) =>
    e.statusCode == 401 && (e.message.toLowerCase().contains('api key') || e.message.toLowerCase().contains('apikey'));

/// True for a 401 caused by the user's token. Only for calls made while logged
/// in: a failed login is also a 401 and must not be passed through this.
bool isTokenProblem(ApiException e) => e.statusCode == 401 && !isKeyProblem(e);

/// Who wrote something, for the screen. The API sends `author`, a name or null.
String byAuthor(String? author) => 'by ${author ?? 'Unknown'}';

/// Said on the log in and register screens. Same wording in all the SimpleAPI demos.
const demoNoticeText =
    'This is a shared demo. Data resets every night. Do not use a real password or any private details.';

/// Shown instead of the API's message when the demo key has no room for more users.
const demoFullMessage = 'The demo is full. It resets every night.';

/// True when a register answer means the key holds all the users it may have.
bool isUserLimit(ApiException e) => e.statusCode == 403 && e.message.toLowerCase().contains('users per key');

class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(demoNoticeText, style: TextStyle(color: scheme.onSecondaryContainer)),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Shown when a request fails, with a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(describeError(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// The leading app bar item of a top-level screen: back to the SimpleAPI home page.
class BackToSimpleApi extends StatelessWidget {
  const BackToSimpleApi({super.key, required this.openUrl});

  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: 'Back to SimpleAPI', icon: const Icon(Icons.arrow_back), onPressed: () => openUrl(homeUrl));
}

/// Centers page content in a readable column on wide screens.
class Centered extends StatelessWidget {
  const Centered({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
  );
}
