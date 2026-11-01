// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io' show Platform;
import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/api_service.dart';

class OnboardingGenre {
  final String key;
  final String label;
  final IconData icon;
  final String searchSeed;
  const OnboardingGenre(this.key, this.label, this.icon, this.searchSeed);
}

const List<OnboardingGenre> kOnboardingGenres = [
  OnboardingGenre('bollywood', 'Bollywood', Icons.movie_filter_rounded, 'bollywood'),
  OnboardingGenre('punjabi', 'Punjabi', Icons.celebration_rounded, 'punjabi'),
  OnboardingGenre('hiphop', 'Hip-Hop', Icons.graphic_eq_rounded, 'hip hop'),
  OnboardingGenre('english', 'English Pop', Icons.language_rounded, 'pop'),
  OnboardingGenre('lofi', 'Lo-Fi / Chill', Icons.nightlight_round, 'lofi chill'),
  OnboardingGenre('devotional', 'Devotional', Icons.self_improvement_rounded, 'devotional bhakti'),
  OnboardingGenre('bhojpuri', 'Bhojpuri', Icons.music_note_rounded, 'bhojpuri'),
  OnboardingGenre('rnb', 'R&B', Icons.mic_external_on_rounded, 'r&b'),
  OnboardingGenre('rock', 'Rock', Icons.electric_bolt_rounded, 'rock'),
  OnboardingGenre('country', 'Country', Icons.landscape_rounded, 'country music'),
  OnboardingGenre('jpop', 'J-Pop', Icons.flare_rounded, 'j-pop'),
  OnboardingGenre('jrnb', 'J-R&B', Icons.spa_rounded, 'japanese r&b'),
  OnboardingGenre('anime', 'Anime', Icons.animation_rounded, 'anime songs'),
  OnboardingGenre('kpop', 'K-Pop', Icons.star_rounded, 'k-pop'),
  OnboardingGenre('latin', 'Latin', Icons.local_fire_department_rounded, 'latin'),
  OnboardingGenre('afrobeats', 'Afrobeats', Icons.public_rounded, 'afrobeats'),
  OnboardingGenre('edm', 'EDM / Dance', Icons.equalizer_rounded, 'edm dance'),
  OnboardingGenre('indie', 'Indie', Icons.explore_rounded, 'indie'),
  OnboardingGenre('classical', 'Classical', Icons.piano_rounded, 'classical'),
  OnboardingGenre('other', 'Something Else', Icons.explore_rounded, 'popular'),
];

const Map<String, List<String>> kCountryGenrePriority = {
  'IN': ['bollywood', 'punjabi', 'english', 'hiphop', 'indie', 'devotional', 'bhojpuri', 'lofi'],
  'US': ['english', 'hiphop', 'rnb', 'rock', 'country', 'edm', 'latin', 'indie'],
  'GB': ['english', 'hiphop', 'edm', 'rock', 'indie', 'rnb'],
  'JP': ['jpop', 'rock', 'jrnb', 'anime', 'hiphop', 'indie'],
  'KR': ['kpop', 'hiphop', 'english', 'rnb', 'indie'],
  'PK': ['bollywood', 'english', 'hiphop', 'indie'],
  'BD': ['bollywood', 'english', 'devotional', 'indie'],
  'CA': ['english', 'hiphop', 'rnb', 'rock', 'country', 'edm'],
  'AU': ['english', 'hiphop', 'edm', 'rock', 'indie'],
  'BR': ['latin', 'hiphop', 'english', 'edm', 'rock'],
  'MX': ['latin', 'english', 'hiphop', 'edm'],
  'NG': ['afrobeats', 'hiphop', 'english', 'rnb'],
  'ZA': ['afrobeats', 'english', 'hiphop', 'edm'],
  'FR': ['english', 'hiphop', 'edm', 'rock', 'indie'],
  'DE': ['edm', 'english', 'hiphop', 'rock'],
  'AE': ['bollywood', 'english', 'hiphop', 'punjabi'],
  'SA': ['english', 'hiphop', 'edm'],
};

const List<String> kDefaultGenrePriority = [
  'bollywood', 'punjabi', 'hiphop', 'english', 'lofi', 'devotional', 'bhojpuri', 'other',
];

String buildArtistSearchSeed({
  required String genreSeed,
  String? countryName,
}) {
  const nativePhrase = <String, String>{
    'bollywood': 'bollywood playback singers',
    'punjabi': 'punjabi singers',
    'bhojpuri': 'bhojpuri singers',
    'devotional bhakti': 'devotional bhajan singers',
    'j-pop': 'j-pop idols and bands',
    'japanese r&b': 'japanese r&b artists',
    'anime songs': 'anime theme song artists',
    'k-pop': 'k-pop idol groups',
    'afrobeats': 'afrobeats artists',
    'latin': 'latin music artists',
    'country music': 'country music singers',
  };

  final phrase = nativePhrase[genreSeed] ?? '$genreSeed artists';

  if (countryName == null) return phrase;

  return 'top $phrase from $countryName';
}

List<OnboardingGenre> genreOrderFor(String? countryCode) {
  final priority = kCountryGenrePriority[countryCode] ?? kDefaultGenrePriority;
  final byKey = {for (final g in kOnboardingGenres) g.key: g};
  final ordered = <OnboardingGenre>[];
  final used = <String>{};
  for (final key in priority) {
    final g = byKey[key];
    if (g != null && used.add(g.key)) ordered.add(g);
  }
  for (final g in kOnboardingGenres) {
    if (used.add(g.key)) ordered.add(g);
  }
  return ordered;
}

class Country {
  final String code;
  final String name;
  const Country(this.code, this.name);

  String get flag =>
      String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + (c - 65)));
}

const List<Country> kCountries = [
  Country('AF', 'Afghanistan'),
  Country('AL', 'Albania'),
  Country('DZ', 'Algeria'),
  Country('AD', 'Andorra'),
  Country('AO', 'Angola'),
  Country('AG', 'Antigua and Barbuda'),
  Country('AR', 'Argentina'),
  Country('AM', 'Armenia'),
  Country('AU', 'Australia'),
  Country('AT', 'Austria'),
  Country('AZ', 'Azerbaijan'),
  Country('BS', 'Bahamas'),
  Country('BH', 'Bahrain'),
  Country('BD', 'Bangladesh'),
  Country('BB', 'Barbados'),
  Country('BY', 'Belarus'),
  Country('BE', 'Belgium'),
  Country('BZ', 'Belize'),
  Country('BJ', 'Benin'),
  Country('BT', 'Bhutan'),
  Country('BO', 'Bolivia'),
  Country('BA', 'Bosnia and Herzegovina'),
  Country('BW', 'Botswana'),
  Country('BR', 'Brazil'),
  Country('BN', 'Brunei'),
  Country('BG', 'Bulgaria'),
  Country('BF', 'Burkina Faso'),
  Country('BI', 'Burundi'),
  Country('CV', 'Cabo Verde'),
  Country('KH', 'Cambodia'),
  Country('CM', 'Cameroon'),
  Country('CA', 'Canada'),
  Country('CF', 'Central African Republic'),
  Country('TD', 'Chad'),
  Country('CL', 'Chile'),
  Country('CN', 'China'),
  Country('CO', 'Colombia'),
  Country('KM', 'Comoros'),
  Country('CG', 'Congo'),
  Country('CD', 'Congo (DRC)'),
  Country('CR', 'Costa Rica'),
  Country('CI', 'Cote d\'Ivoire'),
  Country('HR', 'Croatia'),
  Country('CU', 'Cuba'),
  Country('CY', 'Cyprus'),
  Country('CZ', 'Czechia'),
  Country('DK', 'Denmark'),
  Country('DJ', 'Djibouti'),
  Country('DM', 'Dominica'),
  Country('DO', 'Dominican Republic'),
  Country('EC', 'Ecuador'),
  Country('EG', 'Egypt'),
  Country('SV', 'El Salvador'),
  Country('GQ', 'Equatorial Guinea'),
  Country('ER', 'Eritrea'),
  Country('EE', 'Estonia'),
  Country('SZ', 'Eswatini'),
  Country('ET', 'Ethiopia'),
  Country('FJ', 'Fiji'),
  Country('FI', 'Finland'),
  Country('FR', 'France'),
  Country('GA', 'Gabon'),
  Country('GM', 'Gambia'),
  Country('GE', 'Georgia'),
  Country('DE', 'Germany'),
  Country('GH', 'Ghana'),
  Country('GR', 'Greece'),
  Country('GD', 'Grenada'),
  Country('GT', 'Guatemala'),
  Country('GN', 'Guinea'),
  Country('GW', 'Guinea-Bissau'),
  Country('GY', 'Guyana'),
  Country('HT', 'Haiti'),
  Country('HN', 'Honduras'),
  Country('HU', 'Hungary'),
  Country('IS', 'Iceland'),
  Country('IN', 'India'),
  Country('ID', 'Indonesia'),
  Country('IR', 'Iran'),
  Country('IQ', 'Iraq'),
  Country('IE', 'Ireland'),
  Country('IL', 'Israel'),
  Country('IT', 'Italy'),
  Country('JM', 'Jamaica'),
  Country('JP', 'Japan'),
  Country('JO', 'Jordan'),
  Country('KZ', 'Kazakhstan'),
  Country('KE', 'Kenya'),
  Country('KI', 'Kiribati'),
  Country('KP', 'North Korea'),
  Country('KR', 'South Korea'),
  Country('KW', 'Kuwait'),
  Country('KG', 'Kyrgyzstan'),
  Country('LA', 'Laos'),
  Country('LV', 'Latvia'),
  Country('LB', 'Lebanon'),
  Country('LS', 'Lesotho'),
  Country('LR', 'Liberia'),
  Country('LY', 'Libya'),
  Country('LI', 'Liechtenstein'),
  Country('LT', 'Lithuania'),
  Country('LU', 'Luxembourg'),
  Country('MG', 'Madagascar'),
  Country('MW', 'Malawi'),
  Country('MY', 'Malaysia'),
  Country('MV', 'Maldives'),
  Country('ML', 'Mali'),
  Country('MT', 'Malta'),
  Country('MH', 'Marshall Islands'),
  Country('MR', 'Mauritania'),
  Country('MU', 'Mauritius'),
  Country('MX', 'Mexico'),
  Country('FM', 'Micronesia'),
  Country('MD', 'Moldova'),
  Country('MC', 'Monaco'),
  Country('MN', 'Mongolia'),
  Country('ME', 'Montenegro'),
  Country('MA', 'Morocco'),
  Country('MZ', 'Mozambique'),
  Country('MM', 'Myanmar'),
  Country('NA', 'Namibia'),
  Country('NR', 'Nauru'),
  Country('NP', 'Nepal'),
  Country('NL', 'Netherlands'),
  Country('NZ', 'New Zealand'),
  Country('NI', 'Nicaragua'),
  Country('NE', 'Niger'),
  Country('NG', 'Nigeria'),
  Country('MK', 'North Macedonia'),
  Country('NO', 'Norway'),
  Country('OM', 'Oman'),
  Country('PK', 'Pakistan'),
  Country('PW', 'Palau'),
  Country('PS', 'Palestine'),
  Country('PA', 'Panama'),
  Country('PG', 'Papua New Guinea'),
  Country('PY', 'Paraguay'),
  Country('PE', 'Peru'),
  Country('PH', 'Philippines'),
  Country('PL', 'Poland'),
  Country('PT', 'Portugal'),
  Country('QA', 'Qatar'),
  Country('RO', 'Romania'),
  Country('RU', 'Russia'),
  Country('RW', 'Rwanda'),
  Country('KN', 'Saint Kitts and Nevis'),
  Country('LC', 'Saint Lucia'),
  Country('VC', 'Saint Vincent and the Grenadines'),
  Country('WS', 'Samoa'),
  Country('SM', 'San Marino'),
  Country('ST', 'Sao Tome and Principe'),
  Country('SA', 'Saudi Arabia'),
  Country('SN', 'Senegal'),
  Country('RS', 'Serbia'),
  Country('SC', 'Seychelles'),
  Country('SL', 'Sierra Leone'),
  Country('SG', 'Singapore'),
  Country('SK', 'Slovakia'),
  Country('SI', 'Slovenia'),
  Country('SB', 'Solomon Islands'),
  Country('SO', 'Somalia'),
  Country('ZA', 'South Africa'),
  Country('SS', 'South Sudan'),
  Country('ES', 'Spain'),
  Country('LK', 'Sri Lanka'),
  Country('SD', 'Sudan'),
  Country('SR', 'Suriname'),
  Country('SE', 'Sweden'),
  Country('CH', 'Switzerland'),
  Country('SY', 'Syria'),
  Country('TW', 'Taiwan'),
  Country('TJ', 'Tajikistan'),
  Country('TZ', 'Tanzania'),
  Country('TH', 'Thailand'),
  Country('TL', 'Timor-Leste'),
  Country('TG', 'Togo'),
  Country('TO', 'Tonga'),
  Country('TT', 'Trinidad and Tobago'),
  Country('TN', 'Tunisia'),
  Country('TR', 'Turkey'),
  Country('TM', 'Turkmenistan'),
  Country('TV', 'Tuvalu'),
  Country('UG', 'Uganda'),
  Country('UA', 'Ukraine'),
  Country('AE', 'United Arab Emirates'),
  Country('GB', 'United Kingdom'),
  Country('US', 'United States'),
  Country('UY', 'Uruguay'),
  Country('UZ', 'Uzbekistan'),
  Country('VU', 'Vanuatu'),
  Country('VA', 'Vatican City'),
  Country('VE', 'Venezuela'),
  Country('VN', 'Vietnam'),
  Country('YE', 'Yemen'),
  Country('ZM', 'Zambia'),
  Country('ZW', 'Zimbabwe'),
];

Country? countryByCode(String? code) {
  if (code == null) return null;
  for (final c in kCountries) {
    if (c.code == code) return c;
  }
  return null;
}

Country? detectCountryFromLocale() {
  try {
    if (kIsWeb) return null;
    final raw = Platform.localeName;
    final cleaned = raw.split('.').first;
    final parts = cleaned.split(RegExp(r'[_-]'));
    if (parts.length < 2) return null;
    final region = parts[1].toUpperCase();
    return countryByCode(region);
  } catch (_) {
    return null;
  }
}

Future<Country?> detectCountryReal() async {
  final client = ApiService.httpClient;

  Future<Country?> viaIpApiCo() async {
    final res = await client
        .get(Uri.parse('https://ipapi.co/country/'))
        .timeout(const Duration(milliseconds: 3500));
    if (res.statusCode != 200) return null;
    final code = res.body.trim().toUpperCase();
    if (code.length != 2) return null;
    return countryByCode(code);
  }

  Future<Country?> viaIpwhois() async {
    final res = await client
        .get(Uri.parse('https://ipwho.is/?fields=success,country_code'))
        .timeout(const Duration(milliseconds: 3500));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['success'] != true) return null;
    final code = (json['country_code'] as String?)?.toUpperCase();
    return countryByCode(code);
  }

  final attempts = <Future<Country?>>[
    viaIpApiCo().catchError((_) => null),
    viaIpwhois().catchError((_) => null),
  ];

  try {
    final results = await Future.wait(attempts)
        .timeout(const Duration(seconds: 4), onTimeout: () => const []);
    final codes = results.whereType<Country>().map((c) => c.code).toList();
    if (codes.isEmpty) return detectCountryFromLocale();

    final counts = <String, int>{};
    for (final c in codes) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final winner =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return countryByCode(winner) ?? detectCountryFromLocale();
  } catch (_) {
    return detectCountryFromLocale();
  }
}
