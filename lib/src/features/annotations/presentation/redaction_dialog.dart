import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../application/smart_redaction_service.dart';

class RedactionDialog extends StatefulWidget {
  const RedactionDialog({
    super.key,
    required this.documentText,
    required this.redactionService,
  });

  final String documentText;
  final SmartRedactionService redactionService;

  @override
  State<RedactionDialog> createState() => _RedactionDialogState();
}

class _RedactionDialogState extends State<RedactionDialog> {
  final Set<RedactionCategory> _selectedCategories = RedactionCategory.values.toSet();
  List<RedactionMatch> _detectedMatches = [];
  String _redactedPreviewText = '';

  @override
  void initState() {
    super.initState();
    _performScan();
  }

  void _performScan() {
    final matches = widget.redactionService.scanDocumentForPii(
      widget.documentText,
      categories: _selectedCategories,
    );
    final redacted = widget.redactionService.generateRedactedText(widget.documentText, matches);
    setState(() {
      _detectedMatches = matches;
      _redactedPreviewText = redacted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0x3364748B))),
      title: const Row(
        children: [
          Icon(LucideIcons.shieldAlert, size: 18, color: Color(0xFFEF4444)),
          SizedBox(width: 8),
          Text('Privacy-First Data Masking (Smart Redact)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select PII Categories to Automatically Black Out:', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: RedactionCategory.values.map((cat) {
                final isSelected = _selectedCategories.contains(cat);
                final label = cat.name.toUpperCase();
                return FilterChip(
                  label: Text(label, style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : Colors.white60, fontWeight: FontWeight.bold)),
                  selected: isSelected,
                  selectedColor: const Color(0xFFEF4444),
                  backgroundColor: const Color(0x331E293B),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedCategories.add(cat);
                      } else {
                        _selectedCategories.remove(cat);
                      }
                      _performScan();
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(LucideIcons.scanLine, size: 13, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Text('Detected Sensitive Items: ${_detectedMatches.length}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 160,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x66020617),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x22EF4444)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _redactedPreviewText.isEmpty ? 'No text to preview' : _redactedPreviewText,
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _redactedPreviewText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Redacted document text copied to clipboard!'), duration: Duration(seconds: 2)),
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(LucideIcons.copy, size: 14),
          label: const Text('Copy Redacted PDF Text'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
