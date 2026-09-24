import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/book_setup_view_model.dart';

/// Book title + copyright notice before capture (SPEC 6.10). Other metadata
/// fields are omitted — defaults stay on the project.
class BookSetupScreen extends StatefulWidget {
  const BookSetupScreen({super.key, required this.projectId, this.viewModel});

  final String projectId;
  final BookSetupViewModel? viewModel;

  @override
  State<BookSetupScreen> createState() => _BookSetupScreenState();
}

class _BookSetupScreenState extends State<BookSetupScreen> {
  late final BookSetupViewModel _viewModel;
  final _titleController = TextEditingController();
  bool _fieldsSeeded = false;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        BookSetupViewModel(
          projectId: widget.projectId,
          projectRepository: locator<ProjectRepository>(),
        );
    _viewModel.addListener(_seedFieldsOnce);
    _viewModel.initialize();
  }

  void _seedFieldsOnce() {
    if (_fieldsSeeded || !_viewModel.loaded) return;
    _fieldsSeeded = true;
    _titleController.text = _viewModel.title;
  }

  @override
  void dispose() {
    _viewModel.removeListener(_seedFieldsOnce);
    if (widget.viewModel == null) _viewModel.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final saved = await _viewModel.save();
    if (!saved || !mounted) return;
    context.pushReplacement(AppRoutes.captureFor(widget.projectId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bookSetupTitle)),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (!_viewModel.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('bookSetupTitleField'),
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: l10n.bookSetupTitleField,
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: _viewModel.setTitle,
                ),
                const SizedBox(height: 24),
                Card(
                  key: const ValueKey('bookSetupCopyrightNotice'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.copyrightNoticeTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(l10n.copyrightNoticeBody),
                      ],
                    ),
                  ),
                ),
                CheckboxListTile(
                  key: const ValueKey('bookSetupCopyrightAck'),
                  value: _viewModel.copyrightAcknowledged,
                  onChanged: (value) =>
                      _viewModel.setCopyrightAcknowledged(value ?? false),
                  title: Text(l10n.iUnderstand),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('bookSetupContinueButton'),
                  onPressed: _viewModel.canContinue ? _continue : null,
                  child: Text(l10n.continueToCapture),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
