class IntentAcceptanceDecision {
  final bool accepted;
  final String reason;

  const IntentAcceptanceDecision({
    required this.accepted,
    required this.reason,
  });
}

class IntentAcceptanceGate {
  const IntentAcceptanceGate._();

  static IntentAcceptanceDecision evaluate({
    required String text,
    required String predictedIntent,
    required double confidence,
  }) {
    final normalized = _normalize(text);

    if (normalized.isEmpty) {
      return const IntentAcceptanceDecision(
        accepted: false,
        reason: 'No command was provided.',
      );
    }

    //
    // Very low classifier confidence is rejected.
    //
    // This threshold is deliberately conservative because
    // the semantic plausibility rules below do most of the
    // out-of-domain filtering.
    //
    if (confidence < 0.35) {
      return IntentAcceptanceDecision(
        accepted: false,
        reason:
            'The model is not confident enough that this command belongs '
            'to one of the seven supported intents.',
      );
    }

    final plausible = switch (predictedIntent) {
      'PlayMusic' => _playMusic(normalized),
      'AddToPlaylist' => _addToPlaylist(normalized),
      'GetWeather' => _getWeather(normalized),
      'BookRestaurant' => _bookRestaurant(normalized),
      'RateBook' => _rateBook(normalized),
      'SearchCreativeWork' => _searchCreativeWork(normalized),
      'SearchScreeningEvent' => _searchScreeningEvent(normalized),
      _ => false,
    };

    if (!plausible) {
      return IntentAcceptanceDecision(
        accepted: false,
        reason:
            'This request does not appear to belong to the supported '
            'C-DAC seven-intent command domain.',
      );
    }

    return const IntentAcceptanceDecision(
      accepted: true,
      reason: 'Command accepted.',
    );
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsAny(String text, List<String> terms) {
    for (final term in terms) {
      final pattern = RegExp(r'(^|\s)' + RegExp.escape(term) + r'($|\s)');

      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  static bool _containsPhrase(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  static bool _playMusic(String text) {
    return _containsAny(text, const [
          'play',
          'listen',
          'hear',
          'song',
          'songs',
          'music',
          'album',
          'albums',
          'artist',
          'artists',
          'track',
          'tracks',
          'tune',
        ]) ||
        _containsPhrase(text, const ['listen to', 'want to hear', 'put on']);
  }

  static bool _addToPlaylist(String text) {
    final playlistSignal =
        _containsPhrase(text, const ['playlist', 'play list']) ||
        _containsAny(text, const ['playlist']);

    final addSignal =
        _containsAny(text, const ['add', 'save', 'put', 'include']) ||
        _containsPhrase(text, const ['add to', 'save to', 'put this']);

    return playlistSignal || addSignal;
  }

  static bool _getWeather(String text) {
    return _containsAny(text, const [
          'weather',
          'forecast',
          'temperature',
          'temp',
          'rain',
          'raining',
          'rainy',
          'snow',
          'snowing',
          'sunny',
          'cloudy',
          'wind',
          'windy',
          'humidity',
          'humid',
          'degrees',
          'umbrella',
          'hot',
          'cold',
        ]) ||
        _containsPhrase(text, const [
          'will it rain',
          'going to rain',
          'how hot',
          'how cold',
          'what is it like outside',
        ]);
  }

  static bool _bookRestaurant(String text) {
    return _containsAny(text, const [
          'restaurant',
          'restaurants',
          'table',
          'reservation',
          'reservations',
          'reserve',
          'book',
          'dinner',
          'lunch',
          'breakfast',
          'cuisine',
          'dining',
        ]) ||
        _containsPhrase(text, const [
          'party of',
          'table for',
          'place to eat',
          'book a table',
          'reserve a table',
        ]);
  }

  static bool _rateBook(String text) {
    return _containsAny(text, const [
          'rate',
          'rating',
          'star',
          'stars',
          'review',
        ]) ||
        RegExp(r'\b[0-5]\s+stars?\b').hasMatch(text) ||
        _containsPhrase(text, const ['give this book', 'give the book']);
  }

  static bool _searchCreativeWork(String text) {
    return _containsAny(text, const [
          'find',
          'search',
          'movie',
          'film',
          'book',
          'novel',
          'song',
          'album',
          'track',
          'series',
          'game',
          'title',
        ]) ||
        _containsPhrase(text, const [
          'look for',
          'looking for',
          'show me',
          'find me',
        ]);
  }

  static bool _searchScreeningEvent(String text) {
    return _containsAny(text, const [
          'screening',
          'screenings',
          'showtime',
          'showtimes',
          'cinema',
          'theater',
          'theatre',
          'playing',
          'showing',
        ]) ||
        _containsPhrase(text, const [
          'show time',
          'movie time',
          'movie times',
          'near me tonight',
          'showing near me',
          'playing near me',
          'shows of',
        ]);
  }
}
