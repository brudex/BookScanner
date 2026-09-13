/// Normalized (0.0-1.0) point in the coordinate space of a page image,
/// independent of the source camera preview rotation/transform.
class Point2D {
  const Point2D({required this.x, required this.y});

  final double x;
  final double y;

  Point2D copyWith({double? x, double? y}) =>
      Point2D(x: x ?? this.x, y: y ?? this.y);

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  /// Accepts a raw [Map] rather than `Map<String, Object?>` because values
  /// decoded off a Flutter platform channel arrive as untyped
  /// `Map<Object?, Object?>` even when the outer map was cast — a nested
  /// map's runtime type is never automatically re-cast by `.cast()` on its
  /// parent (SPEC 9.7 platform-channel contract).
  factory Point2D.fromJson(Map json) => Point2D(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is Point2D && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2D($x, $y)';
}

/// Four ordered corners (top-left, top-right, bottom-right, bottom-left) of a
/// detected or manually-adjusted document quadrilateral, in normalized page
/// image coordinates.
class Quad {
  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Point2D topLeft;
  final Point2D topRight;
  final Point2D bottomRight;
  final Point2D bottomLeft;

  /// Default full-frame quad used when no edge detection is available,
  /// e.g. manual-only capture on devices without ML support.
  static const Quad fullFrame = Quad(
    topLeft: Point2D(x: 0, y: 0),
    topRight: Point2D(x: 1, y: 0),
    bottomRight: Point2D(x: 1, y: 1),
    bottomLeft: Point2D(x: 0, y: 1),
  );

  /// Fractional insets of the on-screen capture frame guide, shared with
  /// the capture preview painter so detection's "framed page" fallback
  /// cannot drift from what the user actually aimed at.
  static const double guideHorizontalInset = 0.06;
  static const double guideVerticalInset = 0.08;

  /// The rectangle the capture frame-guide brackets mark. Used when a
  /// paper/background split is visible but corners cannot be fitted
  /// confidently — the user already framed the page to this rect.
  static const Quad captureGuide = Quad(
    topLeft: Point2D(x: guideHorizontalInset, y: guideVerticalInset),
    topRight: Point2D(x: 1 - guideHorizontalInset, y: guideVerticalInset),
    bottomRight: Point2D(
      x: 1 - guideHorizontalInset,
      y: 1 - guideVerticalInset,
    ),
    bottomLeft: Point2D(x: guideHorizontalInset, y: 1 - guideVerticalInset),
  );

  List<Point2D> get points => [topLeft, topRight, bottomRight, bottomLeft];

  Quad copyWith({
    Point2D? topLeft,
    Point2D? topRight,
    Point2D? bottomRight,
    Point2D? bottomLeft,
  }) => Quad(
    topLeft: topLeft ?? this.topLeft,
    topRight: topRight ?? this.topRight,
    bottomRight: bottomRight ?? this.bottomRight,
    bottomLeft: bottomLeft ?? this.bottomLeft,
  );

  Map<String, Object?> toJson() => {
    'topLeft': topLeft.toJson(),
    'topRight': topRight.toJson(),
    'bottomRight': bottomRight.toJson(),
    'bottomLeft': bottomLeft.toJson(),
  };

  factory Quad.fromJson(Map json) => Quad(
    topLeft: Point2D.fromJson(json['topLeft'] as Map),
    topRight: Point2D.fromJson(json['topRight'] as Map),
    bottomRight: Point2D.fromJson(json['bottomRight'] as Map),
    bottomLeft: Point2D.fromJson(json['bottomLeft'] as Map),
  );

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
