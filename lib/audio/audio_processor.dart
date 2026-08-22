// lib/audio/audio_processor.dart
// Conditional export router: routes to Native record/audio_session on IO platforms,
// and to Web Audio API on Web platform.

export 'audio_processor_io.dart'
    if (dart.library.js_interop) 'audio_processor_web.dart';
