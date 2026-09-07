import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('GemmaTimelineService tests', () {
    test('extracts 128K context timeline events and handles seekbar scrub', () {
      final service = GemmaTimelineService();
      final events = service.extractChronology('History of project development document text');

      expect(events, isNotEmpty);
      expect(service.activeEventIndex, equals(0));
      expect(service.activeEvent?.title, contains('Initial'));

      service.setActiveEventIndex(1);
      expect(service.activeEventIndex, equals(1));
      expect(service.activeEvent?.title, contains('Multimodal'));
    });

    test('handles empty document text gracefully', () {
      final service = GemmaTimelineService();
      final events = service.extractChronology('');

      expect(events, isEmpty);
      expect(service.activeEvent, isNull);
    });
  });
}
