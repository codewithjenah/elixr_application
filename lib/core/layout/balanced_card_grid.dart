import 'package:flutter/rendering.dart';

/// Chooses a compact catalog grid without leaving a single card in its last
/// row when a smaller, still comfortable column count is available.
///
/// Callers keep ownership of their cards; this only centralises responsive
/// geometry shared by the trainee and teacher catalogs.
abstract final class BalancedCardGrid {
  static int columnsFor({
    required double availableWidth,
    required int itemCount,
    required double minCardWidth,
    required int maxColumns,
    required double spacing,
  }) {
    if (itemCount <= 1 || availableWidth <= 0) return 1;

    final widthLimitedColumns =
        ((availableWidth + spacing) / (minCardWidth + spacing)).floor();
    var columns = widthLimitedColumns.clamp(1, maxColumns);
    columns = columns.clamp(1, itemCount);

    // A lone final card reads as an accidental orphan. Prefer the largest
    // viable lower count that gives the final row company (5 -> 3 + 2,
    // 9 -> 3 + 3 + 3), while keeping cards at the same established width.
    if (columns > 1 && itemCount % columns == 1) {
      for (var candidate = columns - 1; candidate >= 1; candidate--) {
        if (itemCount % candidate != 1 || candidate == 1) {
          columns = candidate;
          break;
        }
      }
    }
    return columns;
  }
}

/// A fixed-extent Sliver grid which centers its incomplete final row. The
/// standard fixed-count delegate always starts that row at the leading edge.
class BalancedSliverGridDelegate extends SliverGridDelegate {
  const BalancedSliverGridDelegate({
    required this.crossAxisCount,
    required this.childCount,
    required this.mainAxisExtent,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    this.maxSingleCardWidth,
  });

  final int crossAxisCount;
  final int childCount;
  final double mainAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double? maxSingleCardWidth;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final normalChildCrossAxisExtent =
        (constraints.crossAxisExtent -
            crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    final childCrossAxisExtent = childCount == 1 && maxSingleCardWidth != null
        ? normalChildCrossAxisExtent.clamp(0.0, maxSingleCardWidth!)
        : normalChildCrossAxisExtent;
    return _BalancedSliverGridLayout(
      crossAxisCount: crossAxisCount,
      childCount: childCount,
      childCrossAxisExtent: childCrossAxisExtent,
      mainAxisExtent: mainAxisExtent,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      leadingCrossAxisSpace: childCount == 1
          ? (constraints.crossAxisExtent - childCrossAxisExtent) / 2
          : 0,
    );
  }

  @override
  bool shouldRelayout(BalancedSliverGridDelegate oldDelegate) =>
      crossAxisCount != oldDelegate.crossAxisCount ||
      childCount != oldDelegate.childCount ||
      mainAxisExtent != oldDelegate.mainAxisExtent ||
      crossAxisSpacing != oldDelegate.crossAxisSpacing ||
      mainAxisSpacing != oldDelegate.mainAxisSpacing ||
      maxSingleCardWidth != oldDelegate.maxSingleCardWidth;
}

class _BalancedSliverGridLayout extends SliverGridLayout {
  const _BalancedSliverGridLayout({
    required this.crossAxisCount,
    required this.childCount,
    required this.childCrossAxisExtent,
    required this.mainAxisExtent,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.leadingCrossAxisSpace,
  });

  final int crossAxisCount;
  final int childCount;
  final double childCrossAxisExtent;
  final double mainAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double leadingCrossAxisSpace;

  double get _mainAxisStride => mainAxisExtent + mainAxisSpacing;
  int get _lastRowStart =>
      ((childCount - 1) ~/ crossAxisCount) * crossAxisCount;
  int get _lastRowCount => childCount - _lastRowStart;

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final row = index ~/ crossAxisCount;
    final column = index % crossAxisCount;
    if (index >= _lastRowStart && _lastRowCount < crossAxisCount) {
      // Half of the unused track width centers the final row without changing
      // any card's width or the spacing used by complete rows.
      final leadingEmptyTracks = (crossAxisCount - _lastRowCount) / 2;
      final offset =
          leadingCrossAxisSpace +
          leadingEmptyTracks * (childCrossAxisExtent + crossAxisSpacing);
      return SliverGridGeometry(
        scrollOffset: row * _mainAxisStride,
        crossAxisOffset:
            offset + column * (childCrossAxisExtent + crossAxisSpacing),
        mainAxisExtent: mainAxisExtent,
        crossAxisExtent: childCrossAxisExtent,
      );
    }
    return SliverGridGeometry(
      scrollOffset: row * _mainAxisStride,
      crossAxisOffset:
          leadingCrossAxisSpace +
          column * (childCrossAxisExtent + crossAxisSpacing),
      mainAxisExtent: mainAxisExtent,
      crossAxisExtent: childCrossAxisExtent,
    );
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      (scrollOffset ~/ _mainAxisStride) * crossAxisCount;

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      (((scrollOffset + _mainAxisStride - 0.0001) ~/ _mainAxisStride) + 1) *
          crossAxisCount -
      1;

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount == 0) return 0;
    final rows = (childCount + crossAxisCount - 1) ~/ crossAxisCount;
    return rows * _mainAxisStride - mainAxisSpacing;
  }
}
