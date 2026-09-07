import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../application/workspace_providers.dart';
import '../../infrastructure/workspace_preset_store.dart';

final workspacePresetStoreProvider = Provider<WorkspacePresetStore>((ref) {
  return WorkspacePresetStore();
});

final workspacePresetsProvider = FutureProvider<List<WorkspacePreset>>((ref) async {
  final store = ref.watch(workspacePresetStoreProvider);
  return store.readPresets();
});

class WorkspacePresetsDialog extends ConsumerStatefulWidget {
  const WorkspacePresetsDialog({super.key});

  @override
  ConsumerState<WorkspacePresetsDialog> createState() => _WorkspacePresetsDialogState();
}

class _WorkspacePresetsDialogState extends ConsumerState<WorkspacePresetsDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentLayout() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    final currentState = ref.read(workspaceNotifierProvider).value;
    if (currentState != null) {
      final store = ref.read(workspacePresetStoreProvider);
      final preset = WorkspacePreset(
        id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        createdAt: DateTime.now(),
        session: currentState.session,
      );
      await store.savePreset(preset);
      ref.invalidate(workspacePresetsProvider);
      _nameController.clear();
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final presetsAsync = ref.watch(workspacePresetsProvider);

    return AlertDialog(
      backgroundColor: const Color(0xFF18181B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF3F3F46)),
      ),
      title: const Row(
        children: [
          Icon(LucideIcons.layoutGrid, size: 18, color: Color(0xFFA1A1AA)),
          SizedBox(width: 8),
          Text(
            'Workspace Presets & Layout Saver',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save current open tab session as a named preset to instantly restore later:',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Preset name (e.g. Tax Return 2026, Thesis Ch3)',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF27272A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3F3F46)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveCurrentLayout,
                  icon: const Icon(LucideIcons.bookmarkPlus, size: 14),
                  label: Text(_isSaving ? 'Saving...' : 'Save Layout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F3F46),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Saved Workspace Presets:',
              style: TextStyle(color: Color(0xFFFAFAFA), fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3F3F46)),
              ),
              child: presetsAsync.when(
                data: (presets) {
                  if (presets.isEmpty) {
                    return const Center(
                      child: Text('No saved presets yet.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: presets.length,
                    separatorBuilder: (context, index) => const Divider(height: 8, color: Color(0xFF27272A)),
                    itemBuilder: (ctx, index) {
                      final p = presets[index];
                      return Row(
                        children: [
                          const Icon(LucideIcons.folderKanban, size: 16, color: Color(0xFFA1A1AA)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${p.tabCount} open tab(s) • Created ${_formatDate(p.createdAt)}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final notifier = ref.read(workspaceNotifierProvider.notifier);
                              await notifier.restoreSession(p.session);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            icon: const Icon(LucideIcons.play, size: 12),
                            label: const Text('Restore', style: TextStyle(fontSize: 10.5)),
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFFA1A1AA)),
                            onPressed: () async {
                              final store = ref.read(workspacePresetStoreProvider);
                              await store.deletePreset(p.id);
                              ref.invalidate(workspacePresetsProvider);
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading presets: $err', style: const TextStyle(color: Colors.white54))),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
