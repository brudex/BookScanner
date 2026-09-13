import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../domain/models/page_source.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/providers/pdf_rasterizer_provider.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/page_operations_view_model.dart';

/// Presents the 3 ways to bring pages into a composition session (SPEC 6.5
/// "editing": merge/insert/replace from elsewhere) and returns the
/// [PageSource] the user picked, or null if they backed out at any step.
Future<PageSource?> showSourcePickerSheet({
  required BuildContext context,
  required PageOperationsViewModel viewModel,
}) async {
  final l10n = AppLocalizations.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('sourcePickerFromProject'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.composeSourceFromProject),
            onTap: () => Navigator.pop(context, 'project'),
          ),
          ListTile(
            key: const ValueKey('sourcePickerFromPdf'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.composeSourceFromPdf),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
          ListTile(
            key: const ValueKey('sourcePickerFromImage'),
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.composeSourceFromImage),
            onTap: () => Navigator.pop(context, 'image'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;

  switch (choice) {
    case 'project':
      return _pickFromProject(context);
    case 'pdf':
      return _pickFromPdf(context, viewModel);
    case 'image':
      return _pickFromImage();
    default:
      return null;
  }
}

Future<PageSource?> _pickFromProject(BuildContext context) async {
  final projectId = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => const _ProjectPickerSheet(),
  );
  return projectId == null ? null : ProjectPageSource(projectId);
}

Future<PageSource?> _pickFromPdf(
  BuildContext context,
  PageOperationsViewModel viewModel,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  final path = result?.files.single.path;
  if (path == null || !context.mounted) return null;

  final selected = await showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _PdfPagePickerSheet(pdfPath: path, viewModel: viewModel),
  );
  return selected == null
      ? null
      : ExternalPdfPageSource(path, pageIndices: selected);
}

Future<PageSource?> _pickFromImage() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file == null ? null : ImageFilePageSource(file.path);
}

class _ProjectPickerSheet extends StatelessWidget {
  const _ProjectPickerSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: StreamBuilder<List<Project>>(
        stream: locator<ProjectRepository>().watchProjects(
          const ProjectQuery(),
        ),
        builder: (context, snapshot) {
          final projects = snapshot.data ?? const [];
          if (projects.isEmpty) {
            return SizedBox(
              height: 120,
              child: Center(child: Text(l10n.libraryEmptyTitle)),
            );
          }
          return ListView.builder(
            key: const ValueKey('projectPickerList'),
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return ListTile(
                key: ValueKey('projectPickerItem-${project.id}'),
                leading: const Icon(Icons.description_outlined),
                title: Text(project.title),
                subtitle: Text(l10n.pageCount(project.pageOrder.length)),
                onTap: () => Navigator.pop(context, project.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _PdfPagePickerSheet extends StatefulWidget {
  const _PdfPagePickerSheet({required this.pdfPath, required this.viewModel});

  final String pdfPath;
  final PageOperationsViewModel viewModel;

  @override
  State<_PdfPagePickerSheet> createState() => _PdfPagePickerSheetState();
}

class _PdfPagePickerSheetState extends State<_PdfPagePickerSheet> {
  late final Future<List<RasterizedPdfPage>> _thumbnails;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _thumbnails = widget.viewModel.loadPdfThumbnails(widget.pdfPath);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.8,
        child: FutureBuilder<List<RasterizedPdfPage>>(
          future: _thumbnails,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final pages = snapshot.data!;
            if (_selected.isEmpty) {
              _selected.addAll(pages.map((p) => p.pageIndex));
            }
            return Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    key: const ValueKey('pdfPagePickerGrid'),
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                        ),
                    itemCount: pages.length,
                    itemBuilder: (context, index) {
                      final page = pages[index];
                      final isSelected = _selected.contains(page.pageIndex);
                      return GestureDetector(
                        key: ValueKey('pdfPagePickerItem-${page.pageIndex}'),
                        onTap: () => setState(() {
                          if (!_selected.remove(page.pageIndex)) {
                            _selected.add(page.pageIndex);
                          }
                        }),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.memory(
                                Uint8List.fromList(page.pngBytes),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const ValueKey('pdfPagePickerConfirm'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            _selected.toList()..sort(),
                          ),
                    child: Text(l10n.composeAddPagesAction),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
