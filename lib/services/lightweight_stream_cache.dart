// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:collection';

class StreamCacheEntry {
  final String url;
  final DateTime createdAt;
  static const Duration defaultTtl = Duration(hours: 2);

  StreamCacheEntry(this.url) : createdAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) > defaultTtl;
}

class LightweightStreamCache {
  static const int maxSize = 30;
  
  final _cache = LinkedHashMap<String, StreamCacheEntry>();

  String? get(String cacheKey) {
    final entry = _cache[cacheKey];
    
    if (entry == null) return null;
    
    if (entry.isExpired) {
      _cache.remove(cacheKey);
      return null;
    }
    
    _cache.remove(cacheKey);
    _cache[cacheKey] = entry;
    
    return entry.url;
  }

  void set(String cacheKey, String url) {
    if (_cache.containsKey(cacheKey)) {
      _cache.remove(cacheKey);
    }

    while (_cache.length >= maxSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    _cache[cacheKey] = StreamCacheEntry(url);
  }

  void invalidate(String cacheKey) {
    _cache.remove(cacheKey);
  }

  void clear() {
    _cache.clear();
  }

  int get size => _cache.length;

  int get length => _cache.length;

  void removeWhere(bool Function(String key, StreamCacheEntry entry) test) {
    _cache.removeWhere(test);
  }

  Map<String, dynamic> getStats() {
    int expiredCount = 0;
    for (final entry in _cache.values) {
      if (entry.isExpired) expiredCount++;
    }
    return {
      'totalEntries': _cache.length,
      'expiredEntries': expiredCount,
      'maxSize': maxSize,
      'memoryEstimate': '~${_cache.length * 150} bytes',
    };
  }

  void cleanup() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }
}
