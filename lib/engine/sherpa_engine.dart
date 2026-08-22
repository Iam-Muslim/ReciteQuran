// lib/engine/sherpa_engine.dart
// Conditional export router: routes to Native C++ FFI on IO platforms,
// and to WebAssembly via dart:js_interop on Web platform.

export 'sherpa_engine_io.dart'
    if (dart.library.js_interop) 'sherpa_engine_web.dart';
