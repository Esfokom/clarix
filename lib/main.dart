import 'package:clarix/src/app.dart';
import 'package:clarix/src/core/boot.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  await bootstrapClarix();
  runApp(const ClarixApp());
}
