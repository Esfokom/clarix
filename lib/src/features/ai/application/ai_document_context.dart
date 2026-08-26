class AiDocumentContext {
  const AiDocumentContext({
    required this.tabId,
    required this.documentId,
    required this.title,
    required this.filePath,
    this.isMissingFile = false,
  });

  final String tabId;
  final String documentId;
  final String title;
  final String filePath;
  final bool isMissingFile;
}
