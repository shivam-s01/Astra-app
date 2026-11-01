// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:shared_preferences/shared_preferences.dart';

class RegionShelfSeed {
  final String label;
  final String query;
  final String? strapline;
  const RegionShelfSeed(this.label, this.query, [this.strapline]);
}

class UserRegion {
  UserRegion._();

  static const String _kCode = 'onboarding_country_code';
  static const String _kName = 'onboarding_country_name';
  static const String defaultCode = 'IN';

  static String _code = defaultCode;
  static String _name = 'India';
  static bool _loaded = false;

  static String get code => _code;
  static String get name => _name;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _apply(p.getString(_kCode), p.getString(_kName));
    } catch (_) {}
    _loaded = true;
  }

  static void update(String? code, String? name) {
    _apply(code, name);
    _loaded = true;
  }

  static void _apply(String? code, String? name) {
    final c = (code ?? '').trim().toUpperCase();
    if (c.length == 2) {
      _code = c;
      _name = (name ?? '').trim().isNotEmpty ? name!.trim() : c;
    } else {
      _code = defaultCode;
      _name = 'India';
    }
  }

  static String get gl => _code;

  static String get hl => 'en';

  static const Map<String, List<String>> _starterByCountry = {
    'IN': [
      'Arijit Singh', 'Kumar Sanu', 'Udit Narayan', 'Alka Yagnik',
      'Shreya Ghoshal', 'Sonu Nigam', 'Lata Mangeshkar', 'Kishore Kumar',
      'Atif Aslam', 'A. R. Rahman', 'Jubin Nautiyal', 'Sunidhi Chauhan',
      'Mohammed Rafi', 'Asha Bhosle', 'Neha Kakkar', 'Pritam',
    ],
    'PK': [
      'Atif Aslam', 'Rahat Fateh Ali Khan', 'Nusrat Fateh Ali Khan',
      'Arijit Singh', 'Ali Zafar', 'Abida Parveen', 'Kumar Sanu',
      'Alka Yagnik',
    ],
    'BD': [
      'Arijit Singh', 'Kumar Sanu', 'Shreya Ghoshal', 'Atif Aslam',
      'Anupam Roy', 'Habib Wahid', 'Udit Narayan', 'Alka Yagnik',
    ],
    'US': [
      'Taylor Swift', 'Drake', 'The Weeknd', 'Ed Sheeran', 'Billie Eilish',
      'Post Malone', 'Ariana Grande', 'Kendrick Lamar', 'Bruno Mars',
      'Dua Lipa', 'Eminem', 'SZA',
    ],
    'GB': [
      'Ed Sheeran', 'Adele', 'Coldplay', 'Dua Lipa', 'Harry Styles',
      'Sam Smith', 'Arctic Monkeys', 'The Weeknd', 'Taylor Swift',
    ],
    'CA': [
      'Drake', 'The Weeknd', 'Justin Bieber', 'Shawn Mendes', 'Billie Eilish',
      'Taylor Swift', 'Ed Sheeran', 'Post Malone',
    ],
    'AU': [
      'The Kid LAROI', 'Sia', 'Tame Impala', 'Ed Sheeran', 'Dua Lipa',
      'Taylor Swift', 'The Weeknd', 'Billie Eilish',
    ],
    'KR': [
      'BTS', 'BLACKPINK', 'NewJeans', 'IU', 'Stray Kids', 'SEVENTEEN',
      'aespa', 'TWICE',
    ],
    'JP': [
      'Yoasobi', 'Kenshi Yonezu', 'Official HIGE DANdism', 'Ado', 'Fujii Kaze',
      'LiSA', 'Aimer', 'King Gnu',
    ],
    'BR': [
      'Anitta', 'Luan Santana', 'Marília Mendonça', 'Jorge & Mateus',
      'Gusttavo Lima', 'Ivete Sangalo', 'Djavan', 'Caetano Veloso',
    ],
    'MX': [
      'Bad Bunny', 'Peso Pluma', 'Karol G', 'Natanael Cano', 'Christian Nodal',
      'Luis Miguel', 'Junior H', 'Feid',
    ],
    'NG': [
      'Burna Boy', 'Wizkid', 'Davido', 'Rema', 'Asake', 'Tems', 'Ayra Starr',
      'Fela Kuti',
    ],
    'ZA': [
      'Tyla', 'Black Coffee', 'Kabza De Small', 'Master KG', 'Nasty C',
      'Burna Boy', 'Davido', 'Wizkid',
    ],
    'FR': [
      'Aya Nakamura', 'Stromae', 'Jul', 'Ninho', 'Angèle', 'Indila',
      'David Guetta', 'Dua Lipa',
    ],
    'DE': [
      'Rammstein', 'Apache 207', 'Capital Bra', 'Sido', 'Namika',
      'Robin Schulz', 'Ed Sheeran', 'Dua Lipa',
    ],
    'AE': [
      'Arijit Singh', 'Amr Diab', 'Nancy Ajram', 'Atif Aslam', 'Kadim Al Sahir',
      'Shreya Ghoshal', 'The Weeknd', 'Sonu Nigam',
    ],
    'SA': [
      'Rashed Al Majed', 'Mohammed Abdu', 'Amr Diab', 'Nancy Ajram',
      'Kadim Al Sahir', 'Tamer Hosny', 'The Weeknd', 'Ed Sheeran',
    ],
  };

  static const List<String> _globalStarter = [
    'Taylor Swift', 'The Weeknd', 'Ed Sheeran', 'Dua Lipa', 'Drake',
    'Billie Eilish', 'Bruno Mars', 'Coldplay', 'Arijit Singh', 'Bad Bunny',
  ];

  static List<String> starterArtists() =>
      _starterByCountry[_code] ?? _globalStarter;

  static const Map<String, List<RegionShelfSeed>> _shelvesByCountry = {
    'IN': [
      RegionShelfSeed('Fresh finds, old favorites',
          'new releases and old favorites mix playlist'),
      RegionShelfSeed('Old School Romance', 'old school romantic songs playlist',
          'Celebrate love the old fashioned way'),
      RegionShelfSeed('90s Throwback Fun', '90s bollywood songs playlist',
          'From the weird to the wonderful. Relive the magic'),
      RegionShelfSeed('Easy Evenings', 'easy evenings playlist',
          'Comfy and cozy, as evenings should be'),
      RegionShelfSeed('Dancing on your own', 'dancing on your own playlist',
          'Dance your stress away'),
      RegionShelfSeed('Trending community playlists',
          'trending community playlist'),
    ],
    'US': [
      RegionShelfSeed('Today\'s Top Hits', 'today\'s top hits usa playlist'),
      RegionShelfSeed('Hip-Hop Central', 'hip hop hits usa playlist'),
      RegionShelfSeed('Throwback Jams', '2000s throwback hits playlist',
          'Nostalgia on repeat'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
      RegionShelfSeed('Country Roads', 'country hits playlist'),
      RegionShelfSeed('Workout Energy', 'workout hits playlist'),
    ],
    'GB': [
      RegionShelfSeed('UK Top Hits', 'uk top hits playlist'),
      RegionShelfSeed('Britpop Classics', 'britpop classics playlist'),
      RegionShelfSeed('UK Drill & Grime', 'uk grime drill playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
      RegionShelfSeed('Throwback Jams', '2000s throwback hits playlist'),
    ],
    'CA': [
      RegionShelfSeed('Top Hits Canada', 'top hits canada playlist'),
      RegionShelfSeed('Hip-Hop Central', 'hip hop hits playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
      RegionShelfSeed('Throwback Jams', '2000s throwback hits playlist'),
    ],
    'AU': [
      RegionShelfSeed('Top Hits Australia', 'top hits australia playlist'),
      RegionShelfSeed('Indie Aussie', 'australian indie playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
      RegionShelfSeed('Throwback Jams', '2000s throwback hits playlist'),
    ],
    'KR': [
      RegionShelfSeed('K-Pop Hits', 'kpop hits playlist'),
      RegionShelfSeed('K-Pop Girl Groups', 'kpop girl group hits playlist'),
      RegionShelfSeed('K-Ballads', 'korean ballad playlist'),
      RegionShelfSeed('K-Hip-Hop', 'korean hip hop playlist'),
    ],
    'JP': [
      RegionShelfSeed('J-Pop Hits', 'jpop hits playlist'),
      RegionShelfSeed('Anime Openings', 'anime opening songs playlist'),
      RegionShelfSeed('City Pop', 'city pop classics playlist'),
      RegionShelfSeed('J-Rock', 'jrock hits playlist'),
    ],
    'BR': [
      RegionShelfSeed('Sertanejo Hits', 'sertanejo hits playlist'),
      RegionShelfSeed('Funk Brasil', 'funk brasil hits playlist'),
      RegionShelfSeed('MPB Classics', 'mpb classics playlist'),
      RegionShelfSeed('Pagode & Samba', 'pagode samba hits playlist'),
    ],
    'MX': [
      RegionShelfSeed('Regional Mexicano', 'regional mexicano hits playlist'),
      RegionShelfSeed('Reggaeton Hits', 'reggaeton hits playlist'),
      RegionShelfSeed('Latin Pop', 'latin pop hits playlist'),
      RegionShelfSeed('Corridos Tumbados', 'corridos tumbados playlist'),
    ],
    'NG': [
      RegionShelfSeed('Afrobeats Hits', 'afrobeats hits playlist'),
      RegionShelfSeed('Naija Party', 'naija party songs playlist'),
      RegionShelfSeed('Amapiano', 'amapiano hits playlist'),
      RegionShelfSeed('Afro Chill', 'afro chill playlist'),
    ],
    'ZA': [
      RegionShelfSeed('Amapiano Hits', 'amapiano hits playlist'),
      RegionShelfSeed('Afrobeats Hits', 'afrobeats hits playlist'),
      RegionShelfSeed('SA Hip-Hop', 'south african hip hop playlist'),
      RegionShelfSeed('House Grooves', 'south african house playlist'),
    ],
    'PK': [
      RegionShelfSeed('Pakistani Hits', 'pakistani top songs playlist'),
      RegionShelfSeed('Coke Studio Favorites', 'coke studio pakistan playlist'),
      RegionShelfSeed('Qawwali Classics', 'qawwali classics playlist'),
      RegionShelfSeed('Old School Romance', 'old school romantic songs playlist'),
    ],
    'BD': [
      RegionShelfSeed('Bangla Hits', 'bangla top songs playlist'),
      RegionShelfSeed('Old School Romance', 'old school romantic songs playlist'),
      RegionShelfSeed('Bollywood Hits', 'bollywood hits playlist'),
      RegionShelfSeed('Rabindra Sangeet', 'rabindra sangeet playlist'),
    ],
    'FR': [
      RegionShelfSeed('Top Hits France', 'top hits france playlist'),
      RegionShelfSeed('Rap Français', 'rap francais hits playlist'),
      RegionShelfSeed('Chanson Française', 'chanson francaise classics playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
    ],
    'DE': [
      RegionShelfSeed('Top Hits Deutschland', 'top hits deutschland playlist'),
      RegionShelfSeed('Deutschrap', 'deutschrap hits playlist'),
      RegionShelfSeed('Electro & Techno', 'german techno electronic playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
    ],
    'AE': [
      RegionShelfSeed('Arabic Hits', 'arabic top hits playlist'),
      RegionShelfSeed('Bollywood Hits', 'bollywood hits playlist'),
      RegionShelfSeed('Khaleeji Vibes', 'khaleeji songs playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
    ],
    'SA': [
      RegionShelfSeed('Arabic Hits', 'arabic top hits playlist'),
      RegionShelfSeed('Khaleeji Vibes', 'khaleeji songs playlist'),
      RegionShelfSeed('Tarab Classics', 'arabic tarab classics playlist'),
      RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
    ],
  };

  static const List<RegionShelfSeed> _globalShelves = [
    RegionShelfSeed('Global Top Hits', 'global top hits playlist'),
    RegionShelfSeed('Chill Vibes', 'chill pop vibes playlist'),
    RegionShelfSeed('Throwback Jams', '2000s throwback hits playlist',
        'Nostalgia on repeat'),
    RegionShelfSeed('Hip-Hop Central', 'hip hop hits playlist'),
    RegionShelfSeed('Workout Energy', 'workout hits playlist'),
    RegionShelfSeed('Easy Evenings', 'easy evenings playlist',
        'Comfy and cozy, as evenings should be'),
  ];

  static List<RegionShelfSeed> seedShelves() =>
      _shelvesByCountry[_code] ?? _globalShelves;

  static List<String> topArtistsForPicker() {
    final out = <String>[];
    final seen = <String>{};
    for (final a in [...starterArtists(), ..._globalStarter]) {
      if (seen.add(a.toLowerCase())) out.add(a);
    }
    return out;
  }
}
