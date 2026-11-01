// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'audio_prefs.dart';

class AurumImageCache extends CacheManager {
  static const key = 'aurumImageCache';
  static final AurumImageCache _instance = AurumImageCache._();
  factory AurumImageCache() => _instance;

  AurumImageCache._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 14),
            maxNrOfCacheObjects: 4000,
            fileService: _SaverAwareFileService(),
          ),
        );
}

class _SaverAwareFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    final res = await super.get(url, headers: headers);
    if (!AudioPrefs.dataSaverActiveNotifier.value) return res;
    return _LongValidityResponse(res);
  }
}

class _LongValidityResponse implements FileServiceResponse {
  _LongValidityResponse(this._inner);
  final FileServiceResponse _inner;

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 30));

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}
