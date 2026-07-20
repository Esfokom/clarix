class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  static bool isCancel(Object error) =>
      error is CancelToken && error.isCancelled;
  void cancel([String? _]) => _cancelled = true;
}
