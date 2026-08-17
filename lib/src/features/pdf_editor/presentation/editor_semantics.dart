import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EditorSemantics extends StatelessWidget {
  const EditorSemantics({
    required this.controller,
    required this.focusNode,
    required this.child,
    this.readOnlyReason,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;
  final String? readOnlyReason;

  bool get _readOnly => readOnlyReason != null;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('clarix-native-editor-semantics'),
    container: true,
    excludeSemantics: true,
    textField: true,
    readOnly: _readOnly,
    focusable: true,
    focused: focusNode.hasFocus,
    value: controller.text,
    label: _readOnly ? 'PDF text, read only' : 'Editable PDF text',
    hint: readOnlyReason,
    onFocus: focusNode.requestFocus,
    onSetSelection: _readOnly
        ? null
        : (selection) {
            controller.selection = selection;
          },
    onSetText: _readOnly ? null : _setText,
    onCopy: _copy,
    onCut: _readOnly ? null : _cut,
    onPaste: _readOnly ? null : _paste,
    child: child,
  );

  void _setText(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _copy() {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    Clipboard.setData(
      ClipboardData(text: selection.textInside(controller.text)),
    );
  }

  void _cut() {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    _copy();
    controller.value = TextEditingValue(
      text:
          selection.textBefore(controller.text) +
          selection.textAfter(controller.text),
      selection: TextSelection.collapsed(offset: selection.start),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null) return;
    final selection = controller.selection.isValid
        ? controller.selection
        : TextSelection.collapsed(offset: controller.text.length);
    controller.value = TextEditingValue(
      text:
          selection.textBefore(controller.text) +
          pasted +
          selection.textAfter(controller.text),
      selection: TextSelection.collapsed(
        offset: selection.start + pasted.length,
      ),
    );
  }
}
