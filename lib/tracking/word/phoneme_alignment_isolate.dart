// lib/tracking/word/phoneme_alignment_isolate.dart
// Conditional export router: routes to Native dart:isolate worker on IO platforms,
// and to asynchronous StreamController message pump on Web platform.

export 'phoneme_alignment_isolate_protocol.dart';
export 'phoneme_alignment_isolate_io.dart'
    if (dart.library.js_interop) 'phoneme_alignment_isolate_web.dart';
