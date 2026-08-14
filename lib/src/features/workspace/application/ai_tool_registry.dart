import 'dart:convert';

import '../domain/pdf_edit_intent.dart';
import '../domain/pdf_edit_session.dart';
import '../domain/pdf_page_object.dart';
import '../domain/pdf_text_types.dart';
import 'action_permission_service.dart';
import 'pdf_editing_controller.dart';
import '../infrastructure/openai_compatible_provider.dart';

typedef PdfDocumentPathResolver = String? Function(String documentId);

final class AiToolRegistry {
  AiToolRegistry({
    required this.editing,
    required this.permissions,
    required this.pathForDocument,
    this.workspaceId = 'default',
  });

  final PdfEditingController editing;
  final ActionPermissionService permissions;
  final PdfDocumentPathResolver pathForDocument;
  final String workspaceId;

  static const Set<String> names = <String>{
    'inspect_pdf_text_blocks',
    'get_pdf_text_block',
    'replace_pdf_text',
    'format_pdf_text',
    'move_pdf_text_block',
    'resize_pdf_text_block',
    'inspect_pdf_page_objects',
    'move_pdf_page_object',
    'resize_pdf_page_object',
    'rotate_pdf_page_object',
    'undo_pdf_edit',
    'redo_pdf_edit',
    'save_pdf_edits',
  };

  List<Map<String, dynamic>> get schemas => names
      .map(
        (name) => <String, dynamic>{
          'type': 'function',
          'function': <String, dynamic>{
            'name': name,
            'description': _description(name),
            'parameters': _schema(name),
          },
        },
      )
      .toList(growable: false);

  Future<Map<String, Object?>> execute(
    AiToolCall call, {
    required Set<String> allowedDocumentIds,
  }) async {
    if (!names.contains(call.name)) return _error('unknown_tool', call.name);
    try {
      final args = _decode(call.argumentsJson);
      final documentId = _requiredString(args, 'documentId');
      if (!allowedDocumentIds.contains(documentId)) {
        return _error('document_not_allowed', documentId);
      }
      final session = _session(documentId);
      if (call.name == 'inspect_pdf_text_blocks') {
        _rejectUnknown(args, const <String>{'documentId'});
        return <String, Object?>{
          'blocks': session.blocks.map(_blockJson).toList(growable: false),
          'revision': session.revision,
        };
      }
      if (call.name == 'inspect_pdf_page_objects') {
        _rejectUnknown(args, const <String>{'documentId'});
        return <String, Object?>{
          'objects': session.pageObjects
              .map(_pageObjectJson)
              .toList(growable: false),
          'revision': session.revision,
        };
      }
      if (call.name == 'get_pdf_text_block') {
        _rejectUnknown(args, const <String>{'documentId', 'locator'});
        return <String, Object?>{
          'block': _blockJson(_block(session, _locator(args['locator']))),
          'revision': session.revision,
        };
      }
      final revision = _requiredString(args, 'documentRevision');
      final intent = _intent(call.name, args, documentId, revision);
      final decision = await permissions.authorize(
        PermissionContext(
          workspaceId: workspaceId,
          documentId: documentId,
          actionName: call.name,
          intent: intent,
        ),
      );
      if (decision is PermissionRequired) return decision.toJson();
      if (intent is SavePdfEditsIntent) {
        final path = pathForDocument(documentId);
        if (path == null) return _error('document_not_open', documentId);
        final tabId = _tabId(documentId);
        final outcome = await editing.save(tabId, path);
        return <String, Object?>{
          'permission': 'allowed',
          'revision': outcome.newRevision,
          'dirty': false,
          'commandIds': const <String>[],
        };
      }
      final result = await editing.dispatch(
        intent,
        provenance: PdfCommandProvenance.agent,
      );
      final json = _resultJson(result);
      if (intent
          case MovePdfPageObjectIntent(:final locator) ||
              ResizePdfPageObjectIntent(:final locator) ||
              RotatePdfPageObjectIntent(:final locator)) {
        final updated = _session(
          documentId,
        ).pageObjects.firstWhere((object) => object.locator == locator);
        json['resultingMatrix'] = _transformJson(updated.transform);
      }
      return json;
    } on FormatException catch (error) {
      return _error('invalid_arguments', error.message);
    } on PdfEditFailure catch (error) {
      return _error(error.code, error.message);
    } on StateError catch (error) {
      return _error('invalid_state', '$error');
    }
  }

  PdfEditIntent _intent(
    String name,
    Map<String, Object?> args,
    String documentId,
    String revision,
  ) {
    final common = <String>{'documentId', 'documentRevision'};
    switch (name) {
      case 'replace_pdf_text':
        _rejectUnknown(args, <String>{
          ...common,
          'locator',
          'start',
          'end',
          'replacement',
          'caseMatching',
        });
        return ReplacePdfTextIntent(
          documentId: documentId,
          documentRevision: revision,
          locator: _locator(args['locator']),
          range: PdfTextRange(
            _requiredInt(args, 'start'),
            _requiredInt(args, 'end'),
          ),
          replacement: _requiredString(args, 'replacement'),
          caseMatching: args['caseMatching'] as bool? ?? true,
        );
      case 'format_pdf_text':
        _rejectUnknown(args, <String>{
          ...common,
          'locator',
          'start',
          'end',
          'fontFamily',
          'fontSize',
          'fillColorValue',
          'fontWeight',
          'italic',
          'underline',
        });
        return FormatPdfTextIntent(
          documentId: documentId,
          documentRevision: revision,
          locator: _locator(args['locator']),
          range: PdfTextRange(
            _requiredInt(args, 'start'),
            _requiredInt(args, 'end'),
          ),
          patch: PdfTextStylePatch(
            fontFamily: args['fontFamily'] as String?,
            fontSize: (args['fontSize'] as num?)?.toDouble(),
            fillColorValue: args['fillColorValue'] as int?,
            fontWeight: args['fontWeight'] as int?,
            italic: args['italic'] as bool?,
            underline: args['underline'] as bool?,
          ),
        );
      case 'move_pdf_text_block':
      case 'resize_pdf_text_block':
        _rejectUnknown(args, <String>{...common, 'locator', 'bounds'});
        final bounds = _bounds(args['bounds']);
        return name == 'move_pdf_text_block'
            ? MovePdfTextBlockIntent(
                documentId: documentId,
                documentRevision: revision,
                locator: _locator(args['locator']),
                bounds: bounds,
              )
            : ResizePdfTextBlockIntent(
                documentId: documentId,
                documentRevision: revision,
                locator: _locator(args['locator']),
                bounds: bounds,
              );
      case 'move_pdf_page_object':
      case 'resize_pdf_page_object':
        _rejectUnknown(args, <String>{...common, 'locator', 'matrix'});
        final locator = _pageObjectLocator(args['locator']);
        final transform = _transform(args['matrix']);
        return name == 'move_pdf_page_object'
            ? MovePdfPageObjectIntent(
                documentId: documentId,
                documentRevision: revision,
                locator: locator,
                transform: transform,
              )
            : ResizePdfPageObjectIntent(
                documentId: documentId,
                documentRevision: revision,
                locator: locator,
                transform: transform,
              );
      case 'rotate_pdf_page_object':
        _rejectUnknown(args, <String>{
          ...common,
          'locator',
          'radians',
          'centerX',
          'centerY',
        });
        return RotatePdfPageObjectIntent(
          documentId: documentId,
          documentRevision: revision,
          locator: _pageObjectLocator(args['locator']),
          radians: _finiteNumber(args, 'radians'),
          centerX: _optionalFiniteNumber(args, 'centerX'),
          centerY: _optionalFiniteNumber(args, 'centerY'),
        );
      case 'undo_pdf_edit':
        _rejectUnknown(args, common);
        return UndoPdfEditIntent(
          documentId: documentId,
          documentRevision: revision,
        );
      case 'redo_pdf_edit':
        _rejectUnknown(args, common);
        return RedoPdfEditIntent(
          documentId: documentId,
          documentRevision: revision,
        );
      case 'save_pdf_edits':
        _rejectUnknown(args, common);
        return SavePdfEditsIntent(
          documentId: documentId,
          documentRevision: revision,
        );
    }
    throw FormatException('Unsupported mutation tool: $name.');
  }

  PdfEditingSession _session(String documentId) => editing
      .sessionsByTabId
      .values
      .firstWhere((session) => session.documentId == documentId);
  String _tabId(String documentId) => editing.sessionsByTabId.entries
      .firstWhere((entry) => entry.value.documentId == documentId)
      .key;
}

Map<String, Object?> _decode(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Arguments must be a JSON object.');
  }
  return decoded.cast<String, Object?>();
}

void _rejectUnknown(Map<String, Object?> args, Set<String> allowed) {
  final unknown = args.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown argument(s): ${unknown.join(', ')}.');
  }
}

String _requiredString(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key is required.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

PdfTextBlockLocator _locator(Object? value) {
  if (value is! Map) throw const FormatException('locator is required.');
  final map = value.cast<String, Object?>();
  _rejectUnknown(map, const <String>{
    'pageNumber',
    'objectPath',
    'textDigest',
    'geometryDigest',
    'fontFingerprint',
    'sourceRevision',
  });
  return PdfTextBlockLocator(
    pageNumber: _requiredInt(map, 'pageNumber'),
    objectPath:
        (map['objectPath'] as List?)?.cast<int>() ??
        (throw const FormatException('objectPath is required.')),
    textDigest: _requiredString(map, 'textDigest'),
    geometryDigest: _requiredString(map, 'geometryDigest'),
    fontFingerprint: _requiredString(map, 'fontFingerprint'),
    sourceRevision: _requiredString(map, 'sourceRevision'),
  );
}

PdfPageObjectLocator _pageObjectLocator(Object? value) {
  if (value is! Map) throw const FormatException('locator is required.');
  final map = value.cast<String, Object?>();
  _rejectUnknown(map, const <String>{
    'pageNumber',
    'objectPath',
    'type',
    'contentDigest',
    'geometryDigest',
    'sourceRevision',
  });
  final typeName = _requiredString(map, 'type');
  PdfPageObjectType type;
  try {
    type = PdfPageObjectType.values.byName(typeName);
  } on ArgumentError {
    throw FormatException('Unknown PDF object type: $typeName.');
  }
  return PdfPageObjectLocator(
    pageNumber: _requiredInt(map, 'pageNumber'),
    objectPath:
        (map['objectPath'] as List?)?.cast<int>() ??
        (throw const FormatException('objectPath is required.')),
    type: type,
    contentDigest: _requiredString(map, 'contentDigest'),
    geometryDigest: _requiredString(map, 'geometryDigest'),
    sourceRevision: _requiredString(map, 'sourceRevision'),
  );
}

PdfTransform _transform(Object? value) {
  if (value is! Map) throw const FormatException('matrix is required.');
  final map = value.cast<String, Object?>();
  _rejectUnknown(map, const <String>{'a', 'b', 'c', 'd', 'e', 'f'});
  return PdfTransform(
    _finiteNumber(map, 'a'),
    _finiteNumber(map, 'b'),
    _finiteNumber(map, 'c'),
    _finiteNumber(map, 'd'),
    _finiteNumber(map, 'e'),
    _finiteNumber(map, 'f'),
  );
}

double _finiteNumber(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number.');
  }
  return value.toDouble();
}

double? _optionalFiniteNumber(Map<String, Object?> map, String key) =>
    map.containsKey(key) ? _finiteNumber(map, key) : null;

PdfBox _bounds(Object? value) {
  if (value is! Map) throw const FormatException('bounds is required.');
  final map = value.cast<String, Object?>();
  _rejectUnknown(map, const <String>{'left', 'bottom', 'right', 'top'});
  double number(String key) {
    final found = map[key];
    if (found is! num) throw FormatException('bounds.$key is required.');
    return found.toDouble();
  }

  return PdfBox(
    number('left'),
    number('bottom'),
    number('right'),
    number('top'),
  );
}

PdfTextBlock _block(PdfEditingSession session, PdfTextBlockLocator locator) =>
    session.blocks.firstWhere((block) => block.locator == locator);

Map<String, Object?> _blockJson(PdfTextBlock block) => <String, Object?>{
  'locator': _locatorJson(block.locator),
  'text': block.text,
  'bounds': <String, double>{
    'left': block.bounds.left,
    'bottom': block.bounds.bottom,
    'right': block.bounds.right,
    'top': block.bounds.top,
  },
  'editable': block.isEditable,
  'overflow': block.overflow,
};

Map<String, Object?> _pageObjectJson(PdfPageObject object) => <String, Object?>{
  'locator': <String, Object?>{
    'pageNumber': object.locator.pageNumber,
    'objectPath': object.locator.objectPath,
    'type': object.locator.type.name,
    'contentDigest': object.locator.contentDigest,
    'geometryDigest': object.locator.geometryDigest,
    'sourceRevision': object.locator.sourceRevision,
  },
  'bounds': <String, double>{
    'left': object.bounds.left,
    'bottom': object.bounds.bottom,
    'right': object.bounds.right,
    'top': object.bounds.top,
  },
  'matrix': _transformJson(object.transform),
  'capabilities': object.capabilities.map((item) => item.name).toList(),
  'readOnlyReason': object.readOnlyReason?.name,
};

Map<String, double> _transformJson(PdfTransform transform) => <String, double>{
  'a': transform.a,
  'b': transform.b,
  'c': transform.c,
  'd': transform.d,
  'e': transform.translateX,
  'f': transform.translateY,
};

Map<String, Object?> _locatorJson(PdfTextBlockLocator locator) =>
    <String, Object?>{
      'pageNumber': locator.pageNumber,
      'objectPath': locator.objectPath,
      'textDigest': locator.textDigest,
      'geometryDigest': locator.geometryDigest,
      'fontFingerprint': locator.fontFingerprint,
      'sourceRevision': locator.sourceRevision,
    };

Map<String, Object?> _resultJson(PdfEditResult result) => <String, Object?>{
  'permission': 'allowed',
  'revision': result.revision,
  'dirty': result.isDirty,
  'commandIds': result.commandIds,
  'warnings': result.warnings,
  'affectedLocators': result.affectedLocators.map(_locatorJson).toList(),
  if (result.failure case final failure?)
    'error': <String, Object?>{
      'code': failure.code,
      'message': failure.message,
    },
};

Map<String, Object?> _error(String code, String message) => <String, Object?>{
  'error': <String, Object?>{'code': code, 'message': message},
};

String _description(String name) => switch (name) {
  'inspect_pdf_text_blocks' => 'Lists genuine editable PDF text blocks.',
  'get_pdf_text_block' => 'Gets one genuine PDF text block.',
  'replace_pdf_text' => 'Replaces genuine PDF text.',
  'format_pdf_text' => 'Formats genuine PDF text.',
  'move_pdf_text_block' => 'Moves a genuine PDF text block.',
  'resize_pdf_text_block' => 'Resizes a genuine PDF text block.',
  'inspect_pdf_page_objects' => 'Lists genuine native PDF page objects.',
  'move_pdf_page_object' => 'Moves a genuine native PDF page object.',
  'resize_pdf_page_object' => 'Resizes a genuine native PDF page object.',
  'rotate_pdf_page_object' => 'Rotates a genuine native PDF page object.',
  'undo_pdf_edit' => 'Undoes the latest PDF edit.',
  'redo_pdf_edit' => 'Redoes the latest PDF edit.',
  _ => 'Saves PDF edits.',
};

Map<String, Object?> _schema(String name) {
  final properties = <String, Object?>{
    'documentId': <String, Object?>{'type': 'string'},
    if (!name.startsWith('inspect_') && name != 'get_pdf_text_block')
      'documentRevision': <String, Object?>{'type': 'string'},
    if (<String>{
      'get_pdf_text_block',
      'replace_pdf_text',
      'format_pdf_text',
      'move_pdf_text_block',
      'resize_pdf_text_block',
      'move_pdf_page_object',
      'resize_pdf_page_object',
      'rotate_pdf_page_object',
    }.contains(name))
      'locator': name.endsWith('page_object')
          ? _pageObjectLocatorSchema
          : _locatorSchema,
    if (name == 'replace_pdf_text' ||
        name == 'format_pdf_text') ...<String, Object?>{
      'start': <String, Object?>{'type': 'integer', 'minimum': 0},
      'end': <String, Object?>{'type': 'integer', 'minimum': 0},
    },
    if (name == 'replace_pdf_text') ...<String, Object?>{
      'replacement': <String, Object?>{'type': 'string'},
      'caseMatching': <String, Object?>{'type': 'boolean'},
    },
    if (name == 'format_pdf_text') ...<String, Object?>{
      'fontFamily': <String, Object?>{'type': 'string'},
      'fontSize': <String, Object?>{'type': 'number', 'exclusiveMinimum': 0},
      'fillColorValue': <String, Object?>{'type': 'integer'},
      'fontWeight': <String, Object?>{'type': 'integer'},
      'italic': <String, Object?>{'type': 'boolean'},
      'underline': <String, Object?>{'type': 'boolean'},
    },
    if (name == 'move_pdf_text_block' || name == 'resize_pdf_text_block')
      'bounds': _boundsSchema,
    if (name == 'move_pdf_page_object' || name == 'resize_pdf_page_object')
      'matrix': _transformSchema,
    if (name == 'rotate_pdf_page_object') ...<String, Object?>{
      'radians': <String, Object?>{'type': 'number'},
      'centerX': <String, Object?>{'type': 'number'},
      'centerY': <String, Object?>{'type': 'number'},
    },
  };
  final required = <String>[
    'documentId',
    if (!name.startsWith('inspect_') && name != 'get_pdf_text_block')
      'documentRevision',
    if (<String>{
      'get_pdf_text_block',
      'replace_pdf_text',
      'format_pdf_text',
      'move_pdf_text_block',
      'resize_pdf_text_block',
      'move_pdf_page_object',
      'resize_pdf_page_object',
      'rotate_pdf_page_object',
    }.contains(name))
      'locator',
    if (name == 'replace_pdf_text' || name == 'format_pdf_text') ...<String>[
      'start',
      'end',
    ],
    if (name == 'replace_pdf_text') 'replacement',
    if (name == 'move_pdf_text_block' || name == 'resize_pdf_text_block')
      'bounds',
    if (name == 'move_pdf_page_object' || name == 'resize_pdf_page_object')
      'matrix',
    if (name == 'rotate_pdf_page_object') 'radians',
  ];
  return <String, Object?>{
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  };
}

const Map<String, Object?> _locatorSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'pageNumber': <String, Object?>{'type': 'integer', 'minimum': 1},
    'objectPath': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'integer', 'minimum': 0},
    },
    'textDigest': <String, Object?>{'type': 'string'},
    'geometryDigest': <String, Object?>{'type': 'string'},
    'fontFingerprint': <String, Object?>{'type': 'string'},
    'sourceRevision': <String, Object?>{'type': 'string'},
  },
  'required': <String>[
    'pageNumber',
    'objectPath',
    'textDigest',
    'geometryDigest',
    'fontFingerprint',
    'sourceRevision',
  ],
  'additionalProperties': false,
};

const Map<String, Object?> _boundsSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'left': <String, Object?>{'type': 'number'},
    'bottom': <String, Object?>{'type': 'number'},
    'right': <String, Object?>{'type': 'number'},
    'top': <String, Object?>{'type': 'number'},
  },
  'required': <String>['left', 'bottom', 'right', 'top'],
  'additionalProperties': false,
};

const Map<String, Object?> _pageObjectLocatorSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'pageNumber': <String, Object?>{'type': 'integer', 'minimum': 1},
    'objectPath': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'integer', 'minimum': 0},
    },
    'type': <String, Object?>{
      'type': 'string',
      'enum': <String>['text', 'image', 'path', 'form'],
    },
    'contentDigest': <String, Object?>{'type': 'string'},
    'geometryDigest': <String, Object?>{'type': 'string'},
    'sourceRevision': <String, Object?>{'type': 'string'},
  },
  'required': <String>[
    'pageNumber',
    'objectPath',
    'type',
    'contentDigest',
    'geometryDigest',
    'sourceRevision',
  ],
  'additionalProperties': false,
};

const Map<String, Object?> _transformSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'a': <String, Object?>{'type': 'number'},
    'b': <String, Object?>{'type': 'number'},
    'c': <String, Object?>{'type': 'number'},
    'd': <String, Object?>{'type': 'number'},
    'e': <String, Object?>{'type': 'number'},
    'f': <String, Object?>{'type': 'number'},
  },
  'required': <String>['a', 'b', 'c', 'd', 'e', 'f'],
  'additionalProperties': false,
};
