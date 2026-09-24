enum ProjectType { document, book }

enum ProcessingState {
  idle,
  capturing,
  processing,
  reviewReady,
  exporting,
  error,
}

enum PageOrderDirection { leftToRight, rightToLeft }

/// How a book project is photographed (SPEC 5.2 step 2).
enum BookScanMode { singlePage, twoPageSpread }

/// Book/document metadata (SPEC 6.3, 10).
class ProjectMetadata {
  const ProjectMetadata({
    this.author,
    this.language = 'en',
    this.edition,
    this.isbn,
    this.tags = const [],
    this.notes,
    this.startingPageNumber = 1,
    this.pageOrderDirection = PageOrderDirection.leftToRight,
    this.bookScanMode = BookScanMode.twoPageSpread,
  });

  final String? author;
  final String language;
  final String? edition;
  final String? isbn;
  final List<String> tags;
  final String? notes;
  final int startingPageNumber;
  final PageOrderDirection pageOrderDirection;
  final BookScanMode bookScanMode;

  ProjectMetadata copyWith({
    String? author,
    String? language,
    String? edition,
    String? isbn,
    List<String>? tags,
    String? notes,
    int? startingPageNumber,
    PageOrderDirection? pageOrderDirection,
    BookScanMode? bookScanMode,
  }) => ProjectMetadata(
    author: author ?? this.author,
    language: language ?? this.language,
    edition: edition ?? this.edition,
    isbn: isbn ?? this.isbn,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    startingPageNumber: startingPageNumber ?? this.startingPageNumber,
    pageOrderDirection: pageOrderDirection ?? this.pageOrderDirection,
    bookScanMode: bookScanMode ?? this.bookScanMode,
  );

  Map<String, Object?> toJson() => {
    'author': author,
    'language': language,
    'edition': edition,
    'isbn': isbn,
    'tags': tags,
    'notes': notes,
    'startingPageNumber': startingPageNumber,
    'pageOrderDirection': pageOrderDirection.name,
    'bookScanMode': bookScanMode.name,
  };

  factory ProjectMetadata.fromJson(Map<String, Object?> json) =>
      ProjectMetadata(
        author: json['author'] as String?,
        language: json['language'] as String? ?? 'en',
        edition: json['edition'] as String?,
        isbn: json['isbn'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        notes: json['notes'] as String?,
        startingPageNumber: json['startingPageNumber'] as int? ?? 1,
        pageOrderDirection: PageOrderDirection.values.byName(
          json['pageOrderDirection'] as String? ?? 'leftToRight',
        ),
        bookScanMode: BookScanMode.values.byName(
          json['bookScanMode'] as String? ?? 'twoPageSpread',
        ),
      );
}

/// A scan project: either a multi-page document or a book. SPEC 10.
class Project {
  const Project({
    required this.id,
    required this.type,
    required this.title,
    required this.metadata,
    required this.pageOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.processingState,
    this.folderId,
    this.isFavorite = false,
    this.isTrashed = false,
    this.trashedAt,
  });

  final String id;
  final ProjectType type;
  final String title;
  final ProjectMetadata metadata;

  /// Ordered list of page IDs. This is the single source of truth for page
  /// order; PDF export must match it exactly (SPEC 11).
  final List<String> pageOrder;

  final DateTime createdAt;
  final DateTime updatedAt;
  final ProcessingState processingState;
  final String? folderId;
  final bool isFavorite;
  final bool isTrashed;
  final DateTime? trashedAt;

  Project copyWith({
    String? title,
    ProjectMetadata? metadata,
    List<String>? pageOrder,
    DateTime? updatedAt,
    ProcessingState? processingState,
    String? folderId,
    bool? clearFolderId,
    bool? isFavorite,
    bool? isTrashed,
    DateTime? trashedAt,
    bool? clearTrashedAt,
  }) => Project(
    id: id,
    type: type,
    title: title ?? this.title,
    metadata: metadata ?? this.metadata,
    pageOrder: pageOrder ?? this.pageOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    processingState: processingState ?? this.processingState,
    folderId: (clearFolderId ?? false) ? null : (folderId ?? this.folderId),
    isFavorite: isFavorite ?? this.isFavorite,
    isTrashed: isTrashed ?? this.isTrashed,
    trashedAt: (clearTrashedAt ?? false) ? null : (trashedAt ?? this.trashedAt),
  );
}
