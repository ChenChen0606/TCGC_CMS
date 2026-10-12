// Browser history facade for the clinic tabs.
//
// On the web build, tab switches push a `#tab/<index>` entry into the browser
// history so the back/forward arrows walk between tabs. On every other target
// the stub is a no-op. The screens import only this file.
export 'browser_tabs_stub.dart' if (dart.library.html) 'browser_tabs_web.dart';
