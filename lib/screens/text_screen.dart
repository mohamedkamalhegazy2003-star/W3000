import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/settings.dart';
import '../core/strings.dart';
import '../core/ui.dart';
import '../services/translate_service.dart';

/// Shows extracted text (OCR / embedded) with copy, share and translate.
class TextScreen extends StatefulWidget {
  const TextScreen({super.key, required this.title, required this.text, this.autoTranslate = false});

  final String title;
  final String text;
  final bool autoTranslate;

  @override
  State<TextScreen> createState() => _TextScreenState();
}

class _TextScreenState extends State<TextScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.text);

  @override
  void initState() {
    super.initState();
    if (widget.autoTranslate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _translate());
    }
  }

  bool _isArabicText(String t) => TranslateService.detectLanguage(t) == 'ar';

  Future<void> _translate() async {
    final target = AppSettings.instance.translateTarget;
    final src = _c.text;
    final out = await runBusy(
      context,
      () => TranslateService.translate(src, target),
      message: tr('downloadingModel'),
    );
    if (out == null || !mounted) return;
    setState(() => _c.text = out);
  }

  @override
  Widget build(BuildContext context) {
    final empty = _c.text.trim().isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: tr('translate'),
            icon: const Icon(Icons.translate_rounded),
            onPressed: empty ? null : _translate,
          ),
          IconButton(
            tooltip: tr('copy'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: empty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _c.text));
                    if (context.mounted) toast(context, tr('copied'));
                  },
          ),
          IconButton(
            tooltip: tr('share'),
            icon: const Icon(Icons.share_rounded),
            onPressed: empty ? null : () => Share.share(_c.text),
          ),
        ],
      ),
      body: empty
          ? Center(child: Text(tr('noText')))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _c,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                textDirection: _isArabicText(_c.text) ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(fontSize: 17, height: 1.7),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
    );
  }
}
