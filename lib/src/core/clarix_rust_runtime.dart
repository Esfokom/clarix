import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb_base;

import 'ffi/frb_generated.dart' as frb;

/// The single packaged clarix_pdf_oxide.dll runtime used by every Rust call.
class ClarixRustRuntime {
  ClarixRustRuntime._();

  static bool _available = false;
  static bool get isAvailable => _available;
  static Object? _initializationError;
  static Object? get initializationError => _initializationError;
  static Future<bool>? _initializing;

  static Future<bool> ensureInitialized() => _initializing ??= _initialize();

  static Future<bool> _initialize() async {
    try {
      if (Platform.isWindows) {
        final File bundledDll = File(
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}clarix_pdf_oxide.dll',
        );
        await frb.RustLib.init(
          externalLibrary: frb_base.ExternalLibrary.open(
            bundledDll.path,
            debugInfo: 'bundled Clarix Rust runtime',
          ),
        );
      } else {
        await frb.RustLib.init();
      }
      _available = true;
    } catch (error) {
      _available = false;
      _initializationError = error;
    }
    return _available;
  }
}
