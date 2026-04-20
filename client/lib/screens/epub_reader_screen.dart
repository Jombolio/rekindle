import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../core/epub/epub_parser.dart';
import '../providers/download_provider.dart';
import '../providers/reader_provider.dart';

enum _Theme { light, dark, sepia }

class EpubReaderScreen extends ConsumerStatefulWidget {
  final String mediaId;
  final String title;

  const EpubReaderScreen({
    super.key,
    required this.mediaId,
    required this.title,
  });

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  EpubBook? _book;
  int _chapterIndex = 0;
  double _fontSize = 16;
  _Theme _theme = _Theme.light;
  bool _showControls = true;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadEpub();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadEpub() async {
    final downloadState = ref.read(downloadProvider(widget.mediaId));
    final localPath = downloadState.localPath;
    if (localPath == null) return;

    final bytes = await File(localPath).readAsBytes();
    if (!mounted) return;

    final book = EpubParser.parse(bytes);
    final savedChapter = ref.read(readerProvider(widget.mediaId)).currentPage;

    setState(() {
      _book = book;
      _chapterIndex =
          savedChapter.clamp(0, (book.chapters.length - 1).clamp(0, 999999));
    });

    ref
        .read(readerProvider(widget.mediaId).notifier)
        .setTotalPages(book.chapters.length);
  }

  void _prevChapter() {
    if (_chapterIndex > 0) {
      setState(() => _chapterIndex--);
      _saveChapter();
    }
  }

  void _nextChapter() {
    final book = _book;
    if (book == null) return;
    if (_chapterIndex < book.chapters.length - 1) {
      setState(() => _chapterIndex++);
      _saveChapter();
    }
  }

  void _saveChapter() {
    ref
        .read(readerProvider(widget.mediaId).notifier)
        .goToPage(_chapterIndex, widget.mediaId);
  }

  Color get _bgColor => switch (_theme) {
        _Theme.light => Colors.white,
        _Theme.dark => const Color(0xFF1A1A1A),
        _Theme.sepia => const Color(0xFFF5ECD7),
      };

  Color get _fgColor => switch (_theme) {
        _Theme.light => Colors.black87,
        _Theme.dark => const Color(0xFFE0E0E0),
        _Theme.sepia => const Color(0xFF3B2C1A),
      };

  @override
  Widget build(BuildContext context) {
    final book = _book;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) _nextChapter();
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _prevChapter();
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        body: book == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showControls = !_showControls),
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(24, 80, 24, 100),
                      child: HtmlWidget(
                        book.chapters[_chapterIndex].html,
                        textStyle: TextStyle(
                          fontSize: _fontSize,
                          color: _fgColor,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),

                  if (_showControls) ...[
                    // Top bar
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: _bgColor.withValues(alpha: 0.95),
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon:
                                    Icon(Icons.arrow_back, color: _fgColor),
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                              ),
                              Expanded(
                                child: Text(
                                  book.chapters[_chapterIndex].title,
                                  style: TextStyle(
                                    color: _fgColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.palette, color: _fgColor),
                                tooltip: 'Cycle theme',
                                onPressed: () => setState(() {
                                  _theme = _Theme.values[
                                      (_theme.index + 1) %
                                          _Theme.values.length];
                                }),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_decrease,
                                    color: _fgColor),
                                onPressed: () => setState(() =>
                                    _fontSize =
                                        (_fontSize - 1).clamp(10, 32)),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_increase,
                                    color: _fgColor),
                                onPressed: () => setState(() =>
                                    _fontSize =
                                        (_fontSize + 1).clamp(10, 32)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom chapter nav
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: _bgColor.withValues(alpha: 0.95),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left,
                                    color: _fgColor),
                                onPressed: _chapterIndex > 0
                                    ? _prevChapter
                                    : null,
                              ),
                              Expanded(
                                child: Text(
                                  'Chapter ${_chapterIndex + 1}'
                                  ' / ${book.chapters.length}',
                                  style: TextStyle(color: _fgColor),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right,
                                    color: _fgColor),
                                onPressed: _chapterIndex <
                                        book.chapters.length - 1
                                    ? _nextChapter
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
