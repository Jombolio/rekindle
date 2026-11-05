import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api/admin_api.dart';
import '../core/api/api_client.dart';
import '../core/api/libraries_api.dart';
import '../core/import/book_import.dart';
import '../core/models/library.dart';

/// The server side of an import, over the real API.
class ApiBookImportBackend implements BookImportBackend {
  final ApiClient client;
  const ApiBookImportBackend(this.client);

  @override
  Future<List<Library>> getLibraries() => LibrariesApi(client).getAll();

  @override
  Future<BookInspection> inspect({
    required String libraryId,
    required String fileName,
    Uint8List? head,
    String? title,
    String? author,
  }) =>
      AdminApi(client).inspectBook(
        libraryId: libraryId,
        fileName: fileName,
        head: head,
        title: title,
        author: author,
      );

  @override
  Future<void> upload({
    required String libraryId,
    required String path,
    required String fileName,
    required CancelToken cancelToken,
    void Function(int sent, int total)? onProgress,
  }) =>
      AdminApi(client).uploadFile(
        libraryId: libraryId,
        filePath: path,
        fileName: fileName,
        deferScan: true,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );

  @override
  Future<bool> scan(String libraryId) => LibrariesApi(client).scan(libraryId);
}

/// Guided import of a folder of Kindle books or EPUBs: source, preview, import,
/// report. Reads from the folder or device and never changes it.
class BookImportDialog extends StatefulWidget {
  final BookImportBackend backend;
  final BookImportController? controller;
  const BookImportDialog({super.key, required this.backend, this.controller});

  @override
  State<BookImportDialog> createState() => _BookImportDialogState();
}

class _BookImportDialogState extends State<BookImportDialog> {
  late final BookImportController _controller =
      widget.controller ?? BookImportController(backend: widget.backend);

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder of books',
    );
    if (path != null) _controller.chooseSource(path);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final importing = _controller.step == ImportStep.importing;
        return PopScope(
          // Closing mid-import would abandon the scan the uploads are waiting on.
          canPop: !importing,
          child: Dialog(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 680, maxHeight: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Import books',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed:
                              importing ? null : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Flexible(
                    child: switch (_controller.step) {
                      ImportStep.source => _SourceStep(
                          controller: _controller, onPickFolder: _pickFolder),
                      ImportStep.inspecting =>
                        _InspectingStep(controller: _controller),
                      ImportStep.preview =>
                        _PreviewStep(controller: _controller),
                      ImportStep.importing =>
                        _ImportingStep(controller: _controller),
                      ImportStep.report => _ReportStep(
                          controller: _controller,
                          onDone: () => Navigator.pop(context)),
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LibraryField extends StatelessWidget {
  final BookImportController controller;
  const _LibraryField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(controller.library?.id),
      value: controller.library?.id, // ignore: deprecated_member_use
      decoration: const InputDecoration(
          labelText: 'Target library', border: OutlineInputBorder()),
      items: [
        for (final l in controller.libraries)
          DropdownMenuItem(value: l.id, child: Text(l.name)),
      ],
      onChanged: (id) => controller.changeLibrary(
          controller.libraries.where((l) => l.id == id).firstOrNull),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
}

class _SourceStep extends StatelessWidget {
  final BookImportController controller;
  final VoidCallback onPickFolder;
  const _SourceStep({required this.controller, required this.onPickFolder});

  @override
  Widget build(BuildContext context) {
    final canStart = controller.library != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Choose where your books are. Rekindle only reads from there, '
              'and checks each book before anything is uploaded.'),
          const SizedBox(height: 16),
          if (controller.error != null) ...[
            _Message(controller.error!),
            const SizedBox(height: 16),
          ],
          _LibraryField(controller: controller),
          const SizedBox(height: 16),
          for (final path in controller.kindles)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tablet_android_outlined),
                title: const Text('Kindle found'),
                subtitle: Text(path),
                trailing: FilledButton(
                  onPressed:
                      canStart ? () => controller.chooseSource(path) : null,
                  child: const Text('Use this Kindle'),
                ),
              ),
            ),
          if (controller.detecting)
            const LinearProgressIndicator(minHeight: 2)
          else if (controller.kindles.isEmpty)
            Text(
              'No Kindle found. Connect one over USB, or choose a folder.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canStart ? onPickFolder : null,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Choose folder…'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed:
                    controller.detecting ? null : controller.detectKindles,
                icon: const Icon(Icons.refresh),
                label: const Text('Look again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InspectingStep extends StatelessWidget {
  final BookImportController controller;
  const _InspectingStep({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(controller.inspected == 0
              ? 'Looking for books…'
              : 'Checked ${controller.inspected} books…'),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.backToSource,
              child: const Text('Back'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStep extends StatelessWidget {
  final BookImportController controller;
  const _PreviewStep({required this.controller});

  @override
  Widget build(BuildContext context) {
    final books = controller.books;
    final ready = controller.readyCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.error != null) ...[
            _Message(controller.error!),
            const SizedBox(height: 12),
          ],
          _LibraryField(controller: controller),
          const SizedBox(height: 12),
          if (controller.error == null)
            Text(books.isEmpty
                ? 'No books were found in this folder.'
                : '${books.length} found, $ready ready to import.'),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: books.length,
              itemBuilder: (context, i) => _BookRow(
                book: books[i],
                libraryName: controller.library?.name ?? '',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: controller.backToSource,
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              if (controller.error != null)
                FilledButton(
                  onPressed: controller.retryInspection,
                  child: const Text('Try again'),
                )
              else
                FilledButton.icon(
                  onPressed: ready == 0 ? null : controller.startImport,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(ready == 1 ? 'Import 1 book' : 'Import $ready books'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  final ImportBook book;
  final String libraryName;
  const _BookRow({required this.book, required this.libraryName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = book.status == ImportStatus.ready;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (book.author != null) book.author!,
                    'to $libraryName',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (book.reason != null)
                  Text(book.reason!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Chip(
            visualDensity: VisualDensity.compact,
            backgroundColor: ready
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            label: Text(book.status.label),
          ),
        ],
      ),
    );
  }
}

class _ImportingStep extends StatelessWidget {
  final BookImportController controller;
  const _ImportingStep({required this.controller});

  @override
  Widget build(BuildContext context) {
    final book = controller.currentBook;
    final overall = controller.total == 0
        ? 0.0
        : (controller.current + controller.currentFraction) / controller.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.scanning) ...[
            const Text('Updating the library…'),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else ...[
            Text('Uploading ${controller.current + 1} of ${controller.total}'),
            if (book != null)
              Text(book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: controller.currentFraction),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: overall, minHeight: 2),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed:
                    controller.cancelling ? null : controller.cancelImport,
                child: Text(controller.cancelling ? 'Cancelling…' : 'Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportStep extends StatelessWidget {
  final BookImportController controller;
  final VoidCallback onDone;
  const _ReportStep({required this.controller, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final report = controller.report!;
    final imported = report.withOutcome(ImportOutcome.imported).toList();
    final skipped = report.withOutcome(ImportOutcome.skipped).toList();
    final failed = report.withOutcome(ImportOutcome.failed).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${imported.length} imported, ${skipped.length} skipped, '
              '${failed.length} failed.'),
          if (imported.isNotEmpty && report.scanNote == null)
            Text('Imported books appear in the library once its scan finishes.',
                style: Theme.of(context).textTheme.bodySmall),
          if (report.scanNote != null) ...[
            const SizedBox(height: 8),
            _Message(report.scanNote!),
          ],
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _ReportSection(title: 'Imported', results: imported),
                _ReportSection(title: 'Failed', results: failed),
                _ReportSection(title: 'Skipped', results: skipped),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: controller.startOver,
                child: const Text('Import more'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final List<ImportResult> results;
  const _ReportSection({required this.title, required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title, style: theme.textTheme.titleSmall),
        for (final result in results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.book.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (result.reason != null)
                  Text(result.reason!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
