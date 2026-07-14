import 'package:file_picker/file_picker.dart';

typedef DiagnosticPdfPicker = Future<String?> Function();

Future<String?> pickDiagnosticPdf() async {
  final FilePickerResult? result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
    allowMultiple: false,
  );
  return result?.files.single.path;
}
