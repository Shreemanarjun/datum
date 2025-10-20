import 'package:equatable/equatable.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Configuration for paginated queries.
class PaginationConfig extends Equatable {
  /// Number of items per page.
  final int pageSize;

  /// Current page number (for offset-based pagination).
  final int? currentPage;

  /// Cursor for cursor-based pagination.
  final String? cursor;

  /// Creates pagination configuration.
  const PaginationConfig({this.pageSize = 50, this.currentPage, this.cursor});

  @override
  List<Object?> get props => [pageSize, currentPage, cursor];

  @override
  bool get stringify => true;
}

/// Result of a paginated query.
class PaginatedResult<T extends DatumEntity> extends Equatable {
  /// Items in the current page.
  final List<T> items;

  /// Total number of items across all pages.
  final int totalCount;

  /// Current page number.
  final int currentPage;

  /// Total number of pages.
  final int totalPages;

  /// Cursor for the next page (cursor-based pagination).
  final String? nextCursor;

  /// Whether there are more items available.
  final bool hasMore;

  /// Creates a paginated result.
  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    required this.hasMore,
    this.nextCursor,
  });

  /// Creates an empty paginated result.
  const PaginatedResult.empty()
      : items = const [],
        totalCount = 0,
        currentPage = 1,
        totalPages = 0,
        hasMore = false,
        nextCursor = null;

  @override
  List<Object?> get props => [
        items,
        totalCount,
        currentPage,
        totalPages,
        hasMore,
        nextCursor,
      ];

  @override
  bool get stringify => true;
}
