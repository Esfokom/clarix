enum LocalModelFileType { litertlm }

/// Metadata for an on-device model managed by Flutter Gemma.
///
/// This deliberately stores a download identity rather than a path: Flutter
/// Gemma owns its installed files and can restore or remove them safely.
class LocalModelProfile {
  const LocalModelProfile({
    required this.id,
    required this.label,
    required this.modelFileName,
    required this.downloadUrl,
    required this.fileType,
    required this.modelFamily,
  });

  factory LocalModelProfile.gemma4({
    required String id,
    required String label,
    required String modelFileName,
  }) => LocalModelProfile(
    id: id,
    label: label,
    modelFileName: modelFileName,
    downloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/$modelFileName',
    fileType: LocalModelFileType.litertlm,
    modelFamily: 'gemma4',
  );

  /// The built-in local inference model that Clarix can recognize at launch.
  factory LocalModelProfile.gemma4E2b() => LocalModelProfile.gemma4(
    id: 'local-gemma-4-e2b',
    label: 'Gemma 4 E2B (Local)',
    modelFileName: 'gemma-4-E2B-it.litertlm',
  );

  factory LocalModelProfile.fromJson(Map<String, dynamic> json) =>
      LocalModelProfile(
        id: json['id'] as String,
        label: json['label'] as String,
        modelFileName: json['modelFileName'] as String,
        downloadUrl: json['downloadUrl'] as String,
        fileType: LocalModelFileType.values.byName(json['fileType'] as String),
        modelFamily: json['modelFamily'] as String,
      );

  final String id;
  final String label;
  final String modelFileName;
  final String downloadUrl;
  final LocalModelFileType fileType;
  final String modelFamily;

  bool get isGemma4 => modelFamily == 'gemma4';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'modelFileName': modelFileName,
    'downloadUrl': downloadUrl,
    'fileType': fileType.name,
    'modelFamily': modelFamily,
  };

  @override
  bool operator ==(Object other) =>
      other is LocalModelProfile &&
      other.id == id &&
      other.label == label &&
      other.modelFileName == modelFileName &&
      other.downloadUrl == downloadUrl &&
      other.fileType == fileType &&
      other.modelFamily == modelFamily;

  @override
  int get hashCode =>
      Object.hash(id, label, modelFileName, downloadUrl, fileType, modelFamily);
}
