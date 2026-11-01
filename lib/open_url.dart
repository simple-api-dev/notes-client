/// The link opener type, injected so tests need no browser.
library;

/// Opens a link in the current browser tab. Injected so tests need no browser.
typedef UrlOpener = void Function(String url);
