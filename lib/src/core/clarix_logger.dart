import 'package:logger/logger.dart';

final Logger clarixLog = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: false,
    printEmojis: false,
  ),
);
