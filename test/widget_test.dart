import 'package:flutter_test/flutter_test.dart';

import 'package:clarix/main.dart';

void main() {
  testWidgets('renders the chat shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(autoLoadModel: false));

    expect(find.text('Clarix Chat'), findsOneWidget);
    expect(find.text('Model not loaded yet.'), findsOneWidget);
    expect(find.text('Load model'), findsOneWidget);
  });
}
