import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../application/gemma_simulation_service.dart';

class SimulationSliderCard extends StatefulWidget {
  const SimulationSliderCard({
    super.key,
    required this.formula,
    required this.simulationService,
  });

  final SimulationFormula formula;
  final GemmaSimulationService simulationService;

  @override
  State<SimulationSliderCard> createState() => _SimulationSliderCardState();
}

class _SimulationSliderCardState extends State<SimulationSliderCard> {
  @override
  Widget build(BuildContext context) {
    final computedResult = widget.simulationService.evaluateFormula(widget.formula);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x331E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x330EA5E9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sliders, size: 14, color: Color(0xFF38BDF8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.formula.formulaName,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Expression: ${widget.formula.expression}',
            style: const TextStyle(color: Color(0xFF7DD3FC), fontFamily: 'monospace', fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          ...widget.formula.variables.map((variable) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${variable.name}: ${variable.value.toStringAsFixed(1)} ${variable.unit}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: const Color(0xFF38BDF8),
                    inactiveTrackColor: const Color(0x3364748B),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: variable.value.clamp(variable.min, variable.max),
                    min: variable.min,
                    max: variable.max,
                    onChanged: (val) {
                      setState(() {
                        variable.value = val;
                      });
                    },
                  ),
                ),
              ],
            );
          }),
          const Divider(height: 12, color: Color(0x22FFFFFF)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Calculated Result:', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x440EA5E9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF38BDF8)),
                ),
                child: Text(
                  '$computedResult ${widget.formula.outputUnit}',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
