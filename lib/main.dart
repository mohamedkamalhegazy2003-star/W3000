import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  pdfrxFlutterInitialize();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('WPDF')))));
}
