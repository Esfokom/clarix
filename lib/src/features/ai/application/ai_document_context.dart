import 'agent_run_controller.dart';

class AiDocumentContext {
  const AiDocumentContext({
    required this.tabId,
    required this.documentId,
    required this.title,
    required this.filePath,
    required this.editorRevision,
    this.agentController,
    this.isMissingFile = false,
  });

  final String tabId;
  final String documentId;
  final String title;
  final String filePath;
  final int editorRevision;
  final AgentRunController? agentController;
  final bool isMissingFile;
}
