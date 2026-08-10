import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ReaderBackgroundStore {
  Future<String> importImage(String sourcePath) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'reader-backgrounds'));
    await directory.create(recursive: true);
    final extension = path.extension(sourcePath).isEmpty
        ? '.png'
        : path.extension(sourcePath);
    final target = File(
      path.join(
        directory.path,
        'background_${DateTime.now().microsecondsSinceEpoch}$extension',
      ),
    );
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<bool> exists(String storedPath) => File(storedPath).exists();
}
