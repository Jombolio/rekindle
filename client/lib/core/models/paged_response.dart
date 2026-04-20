class PagedResponse<T> {
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  const PagedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;
}
