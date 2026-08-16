import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 60),
  responseDataCallback: (data) => writeResponseData(
    data,
    testOutputFilename: 'phase1-large-document-profile',
    destinationDirectory: 'build/editing_phase1',
  ),
);
