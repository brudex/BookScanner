import 'package:flutter/material.dart';

/// Shows a single-line text-input [AlertDialog], used by rename/create/
/// edit-tags flows across the app.
///
/// The [TextEditingController] is owned by the dialog's own [State] rather
/// than by the caller, so it's disposed only when the dialog widget itself
/// is actually removed from the tree. Disposing it manually right after
/// `showDialog`'s future resolves races the dialog's closing (reverse)
/// transition, which can still be rebuilding the [TextField] for a frame or
/// two — that race is what caused "used after disposed" exceptions here.
Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  required String label,
  String initialText = '',
  required String cancelLabel,
  required String saveLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _TextInputDialog(
      title: title,
      label: label,
      initialText: initialText,
      cancelLabel: cancelLabel,
      saveLabel: saveLabel,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialText,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String title;
  final String label;
  final String initialText;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
