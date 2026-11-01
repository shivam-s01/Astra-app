// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'api_service.dart';
import 'user_region.dart';

class ArtistPickerLoader {
  ArtistPickerLoader._();

  static String _key(String n) => n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<List<ArtistSimple>> buildInitialList({
    required List<List<ArtistSimple>> genreBuckets,
    required bool includeSaavn,
    int cap = 60,
    int curatedCount = 18,
  }) async {
    List<ArtistSimple> curated = const [];
    try {
      curated = await ApiService.resolveCuratedArtists(
        UserRegion.topArtistsForPicker(),
        max: curatedCount,
        includeSaavn: includeSaavn,
      ).timeout(const Duration(seconds: 6), onTimeout: () => <ArtistSimple>[]);
    } catch (_) {}

    final merged = <ArtistSimple>[];
    final seen = <String>{};

    void add(ArtistSimple a) {
      if (a.name.isEmpty) return;
      if (seen.add(_key(a.name))) merged.add(a);
    }

    for (final a in curated) {
      add(a);
    }

    var col = 0;
    var added = true;
    while (added && merged.length < cap) {
      added = false;
      for (final b in genreBuckets) {
        if (col < b.length) {
          add(b[col]);
          added = true;
        }
      }
      col++;
    }
    return merged.take(cap).toList();
  }

  static Future<List<ArtistSimple>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      await UserRegion.load();
      return await ApiService.searchArtistsByName(
        q,
        limit: 15,
        includeSaavn: UserRegion.code == 'IN',
      );
    } catch (_) {
      return const [];
    }
  }
}
