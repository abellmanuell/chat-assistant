import 'package:flutter/material.dart';

import 'open_assistant.dart';

void main() => runApp(const MaterialApp(home: Home()));

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => openAssistant(context),
        child: const Text('Open assistant'),
      ),
    ),
  );
}
