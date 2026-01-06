// FILE: lib/screens/assistant_standalone_screen.dart
//
// Simple wrapper screen around AssistantSheet.

import 'package:flutter/material.dart';
import '../widgets/assistant_sheet.dart';

class AssistantStandaloneScreen extends StatelessWidget {
  const AssistantStandaloneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: const AssistantSheet(),
    );
  }
}
