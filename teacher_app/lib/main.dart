import 'package:flutter/material.dart';

void main() {
  runApp(const ElixrTeacherApp());
}

class ElixrTeacherApp extends StatelessWidget {
  const ElixrTeacherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elixr Teacher',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Elixr Teacher'),
        ),
      ),
    );
  }
}
