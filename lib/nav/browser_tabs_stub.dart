// Non-web fallback for `browser_tabs.dart`. Desktop / mobile builds have no
// browser history to walk, so every call is a no-op.
bool get browserHistoryEnabled => false;

void initTabHistory(void Function(int index) onTab) {}

void pushTabHistory(int index) {}

void disposeTabHistory() {}
