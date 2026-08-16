import 'action_permission_service.dart';
import '../infrastructure/openai_compatible_provider.dart';

typedef PdfDocumentPathResolver = String? Function(String documentId);

/// Phase 1 keeps AI editing read-only. Agent mutation is introduced in Phase 3
/// after it can target the same Rust command authority as manual editing.
final class AiToolRegistry {
  AiToolRegistry({
    required this.permissions,
    required this.pathForDocument,
    this.workspaceId = 'default',
  });

  final ActionPermissionService permissions;
  final PdfDocumentPathResolver pathForDocument;
  final String workspaceId;

  static const Set<String> names = <String>{};

  List<Map<String, dynamic>> get schemas => const <Map<String, dynamic>>[];

  Future<Map<String, Object?>> execute(
    AiToolCall call, {
    required Set<String> allowedDocumentIds,
  }) async => <String, Object?>{
    'status': 'error',
    'code': 'editing_authority_unavailable',
    'message':
        'AI PDF mutation is deferred until it uses the Rust editing authority.',
  };
}
