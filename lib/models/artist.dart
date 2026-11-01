// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'song.dart';

enum ArtistSource { youtube, saavn }

class ArtistAlbum {
  final String id;
  final String name;
  final String artworkUrl;
  final String? year;
  final String type;

  ArtistAlbum({
    required this.id,
    required this.name,
    required this.artworkUrl,
    this.year,
    this.type = 'album',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artworkUrl': artworkUrl,
        'year': year,
        'type': type,
      };

  factory ArtistAlbum.fromJson(Map<String, dynamic> json) => ArtistAlbum(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        artworkUrl: (json['artworkUrl'] ?? '').toString(),
        year: json['year']?.toString(),
        type: (json['type'] ?? 'album').toString(),
      );
}

class AlbumRelatedShelf {
  final String title;
  final List<ArtistAlbum> albums;

  AlbumRelatedShelf({required this.title, required this.albums});
}

class RelatedArtist {
  final String id;
  final String name;
  final String imageUrl;

  RelatedArtist({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
      };

  factory RelatedArtist.fromJson(Map<String, dynamic> json) => RelatedArtist(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        imageUrl: (json['imageUrl'] ?? '').toString(),
      );
}

class Artist {
  final String id;
  final String name;
  final String imageUrl;
  final int followerCount;
  final bool isVerified;
  final String bio;
  final List<Song> topSongs;
  final List<ArtistAlbum> topAlbums;
  final List<ArtistAlbum> singles;
  final ArtistSource source;
  final String? bannerUrl;
  final List<RelatedArtist> relatedArtists;

  Artist({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.followerCount,
    required this.isVerified,
    required this.bio,
    required this.topSongs,
    required this.topAlbums,
    required this.singles,
    this.source = ArtistSource.youtube,
    this.bannerUrl,
    this.relatedArtists = const [],
  });
}
