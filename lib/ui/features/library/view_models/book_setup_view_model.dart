import 'package:flutter/foundation.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/project_repository.dart';

/// Collects optional book metadata before the first capture (SPEC 5.2
/// step 2, 6.3, 6.10).
class BookSetupViewModel extends ChangeNotifier {
  BookSetupViewModel({
    required this.projectId,
    required ProjectRepository projectRepository,
  }) : _projectRepository = projectRepository;

  final String projectId;
  final ProjectRepository _projectRepository;

  Project? _project;
  bool _loaded = false;
  bool get loaded => _loaded;

  String title = '';
  String author = '';
  String language = 'en';
  String edition = '';
  String isbn = '';
  String tags = '';
  String notes = '';
  int startingPageNumber = 1;
  BookScanMode bookScanMode = BookScanMode.twoPageSpread;
  PageOrderDirection pageOrderDirection = PageOrderDirection.leftToRight;
  bool copyrightAcknowledged = false;

  bool get canContinue => _loaded && copyrightAcknowledged;

  Future<void> initialize() async {
    _project = await _projectRepository.getProject(projectId);
    final project = _project;
    if (project != null) {
      title = project.title;
      author = project.metadata.author ?? '';
      language = project.metadata.language;
      edition = project.metadata.edition ?? '';
      isbn = project.metadata.isbn ?? '';
      tags = project.metadata.tags.join(', ');
      notes = project.metadata.notes ?? '';
      startingPageNumber = project.metadata.startingPageNumber;
      bookScanMode = project.metadata.bookScanMode;
      pageOrderDirection = project.metadata.pageOrderDirection;
    }
    _loaded = true;
    notifyListeners();
  }

  void setTitle(String value) {
    title = value;
    notifyListeners();
  }

  void setAuthor(String value) {
    author = value;
    notifyListeners();
  }

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }

  void setEdition(String value) {
    edition = value;
    notifyListeners();
  }

  void setIsbn(String value) {
    isbn = value;
    notifyListeners();
  }

  void setTags(String value) {
    tags = value;
    notifyListeners();
  }

  void setNotes(String value) {
    notes = value;
    notifyListeners();
  }

  void setStartingPageNumber(String value) {
    startingPageNumber = int.tryParse(value.trim()) ?? 1;
    if (startingPageNumber < 1) startingPageNumber = 1;
    notifyListeners();
  }

  void setBookScanMode(BookScanMode value) {
    bookScanMode = value;
    notifyListeners();
  }

  void setPageOrderDirection(PageOrderDirection value) {
    pageOrderDirection = value;
    notifyListeners();
  }

  void setCopyrightAcknowledged(bool value) {
    copyrightAcknowledged = value;
    notifyListeners();
  }

  /// Persists the book title. Other metadata keeps project defaults.
  /// Returns false if the project is missing or copyright is not acknowledged.
  Future<bool> save() async {
    final project = _project;
    if (project == null || !copyrightAcknowledged) return false;
    final trimmedTitle = title.trim();
    await _projectRepository.updateProject(
      project.copyWith(
        title: trimmedTitle.isEmpty ? project.title : trimmedTitle,
        updatedAt: DateTime.now(),
      ),
    );
    return true;
  }
}
