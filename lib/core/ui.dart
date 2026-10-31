import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/pdf_tools.dart';
import 'strings.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Runs [job] behind a blocking progress dialog.
Future<T?> runBusy<T>(BuildContext context, Future<T> Function() job, {String? message}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 20),
            Expanded(child: Text(message ?? tr('working'))),
          ],
        ),
      ),
    ),
  );
  try {
    return await job();
  } catch (e) {
    if (context.mounted) toast(context, '${tr('error')}: $e');
    return null;
  } finally {
    nav.pop();
  }
}

/// Lets the user pick where to save [bytes] or share them.
Future<void> saveOrShare(BuildContext context, String fileName, Uint8List bytes) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt_rounded),
            title: Text(tr('saveAs')),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: Text(tr('share')),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'save') {
    final out = await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: bytes,
      type: FileType.any,
    );
    if (out != null && context.mounted) toast(context, tr('saved'));
  } else {
    final path = await PdfTools.writeTemp(fileName, bytes);
    await Share.shareXFiles([XFile(path)]);
  }
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  bool multiline = false,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        textDirection: null,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('ok'))),
      ],
    ),
  );
}
