/// Entry point of the Notes sample app.
library;

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_state.dart';
import 'open_url_web.dart';

void main() {
  runApp(NotesApp(state: AppState(), openUrl: openInSameTab));
}
