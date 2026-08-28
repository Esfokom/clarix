import 'dart:ffi';

import 'package:pdfium_flutter/pdfium_flutter.dart';

/// Resolves a page-object path into a native page object, descending through
/// form XObjects for nested paths. Returns a null handle (address 0) when the
/// path cannot be resolved.
FPDF_PAGEOBJECT objectAtPdfiumPath(FPDF_PAGE page, List<int> path) {
  if (path.isEmpty) return nullptr.cast<fpdf_pageobject_t__>();
  var object = pdfiumBindings.FPDFPage_GetObject(page, path.first);
  for (var index = 1; index < path.length; index++) {
    if (object.address == 0 ||
        pdfiumBindings.FPDFPageObj_GetType(object) != FPDF_PAGEOBJ_FORM) {
      return nullptr.cast<fpdf_pageobject_t__>();
    }
    object = pdfiumBindings.FPDFFormObj_GetObject(object, path[index]);
  }
  return object;
}
