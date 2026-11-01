/// The app widget: theme and the single home screen.
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'open_url.dart';
import 'screens/notes_screen.dart';

class NotesApp extends StatelessWidget {
  const NotesApp({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes API sample | SimpleAPI',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0066CC),
        useMaterial3: true,
        // A slightly smaller title so "SimpleAPI Notes" never truncates at 360px wide.
        appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      ),
      // The app opens straight on content.
      home: NotesScreen(state: state, openUrl: openUrl),
    );
  }
}
