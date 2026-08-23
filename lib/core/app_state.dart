enum SupportedLanguage { english, hindi }

extension SupportedLanguageCode on SupportedLanguage {
  String get code {
    switch (this) {
      case SupportedLanguage.english:
        return 'en';
      case SupportedLanguage.hindi:
        return 'hi';
    }
  }
}
