import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/ai/ai.dart';

void main() {
  group('GemmaSimulationService tests', () {
    test('parses formula schemas and evaluates live values', () {
      final service = GemmaSimulationService();
      final formulas = service.parseFormulasFromJson('Physics formulas document text');

      expect(formulas, isNotEmpty);
      expect(formulas.first.formulaName, contains('Einstein'));
      
      final result = service.evaluateFormula(formulas.first);
      expect(result, greaterThan(0));
    });

    test('serializes and deserializes simulation variables to JSON', () {
      final variable = SimulationVariable(
        name: 'Mass',
        value: 25.0,
        min: 0.0,
        max: 100.0,
        unit: 'kg',
      );

      final json = variable.toJson();
      final restored = SimulationVariable.fromJson(json);

      expect(restored.name, equals('Mass'));
      expect(restored.value, equals(25.0));
      expect(restored.unit, equals('kg'));
    });
  });
}
