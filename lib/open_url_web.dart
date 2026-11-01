/// Opens links in the current browser tab.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void openInSameTab(String url) {
  globalContext.callMethod('open'.toJS, url.toJS, '_self'.toJS);
}
