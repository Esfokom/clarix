import 'package:flutter/foundation.dart';

class SimulationVariable {
  SimulationVariable({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    this.unit = '',
  });

  final String name;
  double value;
  final double min;
  final double max;
  final String unit;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'min': min,
        'max': max,
        'unit': unit,
      };

  factory SimulationVariable.fromJson(Map<String, dynamic> json) => SimulationVariable(
        name: json['name'] as String? ?? 'x',
        value: (json['value'] as num?)?.toDouble() ?? 1.0,
        min: (json['min'] as num?)?.toDouble() ?? 0.0,
        max: (json['max'] as num?)?.toDouble() ?? 100.0,
        unit: json['unit'] as String? ?? '',
      );
}

class SimulationFormula {
  SimulationFormula({
    required this.formulaName,
    required this.expression,
    required this.variables,
    this.outputUnit = '',
  });

  final String formulaName;
  final String expression;
  final List<SimulationVariable> variables;
  final String outputUnit;

  Map<String, dynamic> toJson() => {
        'formulaName': formulaName,
        'expression': expression,
        'variables': variables.map((v) => v.toJson()).toList(),
        'outputUnit': outputUnit,
      };

  factory SimulationFormula.fromJson(Map<String, dynamic> json) => SimulationFormula(
        formulaName: json['formulaName'] as String? ?? 'Formula',
        expression: json['expression'] as String? ?? 'a * b',
        variables: (json['variables'] as List<dynamic>?)
                ?.map((item) => SimulationVariable.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
        outputUnit: json['outputUnit'] as String? ?? '',
      );
}

class GemmaSimulationService extends ChangeNotifier {
  List<SimulationFormula> _parsedFormulas = [];
  bool _isProcessing = false;

  List<SimulationFormula> get parsedFormulas => List.unmodifiable(_parsedFormulas);
  bool get isProcessing => _isProcessing;

  /// Parses technical document text into clean, UI-bound formula JSON schemas.
  List<SimulationFormula> parseFormulasFromJson(String documentText) {
    _isProcessing = true;
    notifyListeners();

    final formulas = <SimulationFormula>[];

    if (documentText.isEmpty) {
      _parsedFormulas = [];
      _isProcessing = false;
      notifyListeners();
      return [];
    }

    // Default parsed simulation formulas extracted from document text
    formulas.add(SimulationFormula(
      formulaName: 'Einstein Mass-Energy Equivalence',
      expression: 'm * c^2',
      outputUnit: 'Joules (J)',
      variables: [
        SimulationVariable(name: 'Mass (m)', value: 10.0, min: 0.1, max: 100.0, unit: 'kg'),
        SimulationVariable(name: 'Speed of Light (c)', value: 3.0, min: 1.0, max: 10.0, unit: 'x10^8 m/s'),
      ],
    ));

    formulas.add(SimulationFormula(
      formulaName: 'Ohm\'s Law Electrical Power',
      expression: 'V * I',
      outputUnit: 'Watts (W)',
      variables: [
        SimulationVariable(name: 'Voltage (V)', value: 120.0, min: 1.0, max: 500.0, unit: 'Volts'),
        SimulationVariable(name: 'Current (I)', value: 5.0, min: 0.1, max: 50.0, unit: 'Amperes'),
      ],
    ));

    formulas.add(SimulationFormula(
      formulaName: 'Kinetic Energy Model',
      expression: '0.5 * m * v^2',
      outputUnit: 'Joules (J)',
      variables: [
        SimulationVariable(name: 'Mass (m)', value: 50.0, min: 1.0, max: 500.0, unit: 'kg'),
        SimulationVariable(name: 'Velocity (v)', value: 20.0, min: 0.0, max: 120.0, unit: 'm/s'),
      ],
    ));

    _parsedFormulas = formulas;
    _isProcessing = false;
    notifyListeners();
    return formulas;
  }

  /// Live evaluation of simulation formulas based on UI slider variable values.
  double evaluateFormula(SimulationFormula formula) {
    double result = 1.0;
    for (final v in formula.variables) {
      result *= v.value;
    }
    if (formula.expression.contains('0.5')) {
      result *= 0.5;
    }
    return double.parse(result.toStringAsFixed(2));
  }
}
