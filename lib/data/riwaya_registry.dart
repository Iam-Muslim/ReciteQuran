import 'dart:convert';
import 'package:flutter/services.dart';

import 'riwaya_descriptor.dart';

class RiwayaRegistry {
  RiwayaRegistry._(this._byId);

  final Map<String, RiwayaDescriptor> _byId;

  static const List<String> candidateAssetPaths = [
    'packages/recite_quran/assets/json/riwayat.json',
    'assets/json/riwayat.json',
    'packages/recitation_engine/assets/riwayat.json',
    'assets/riwayat.json',
  ];

  static Future<RiwayaRegistry> load([String? customAssetPath]) async {
    final paths = customAssetPath != null ? [customAssetPath] : candidateAssetPaths;
    for (final path in paths) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        return fromJsonString(jsonStr);
      } catch (_) {
        continue;
      }
    }
    throw StateError('Could not find riwayat registry in any candidate asset path: $paths');
  }

  static RiwayaRegistry fromJsonString(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final rows = root['riwayat'];
    if (rows is! List || rows.isEmpty) {
      throw ArgumentError('riwayat.json must contain a non-empty "riwayat" list');
    }

    final map = <String, RiwayaDescriptor>{};
    for (final row in rows) {
      final descriptor =
          RiwayaDescriptor.fromJson(row as Map<String, dynamic>);
      if (map.containsKey(descriptor.id)) {
        throw ArgumentError('duplicate riwaya id "${descriptor.id}"');
      }
      map[descriptor.id] = descriptor;
    }
    return RiwayaRegistry._(map);
  }

  List<RiwayaDescriptor> get all => List.unmodifiable(_byId.values);

  RiwayaDescriptor? tryById(String id) => _byId[id];

  RiwayaDescriptor byId(String id) {
    final descriptor = _byId[id];
    if (descriptor == null) {
      throw ArgumentError(
        'unknown riwaya "$id"; registered: ${_byId.keys.join(', ')}',
      );
    }
    return descriptor;
  }
}
