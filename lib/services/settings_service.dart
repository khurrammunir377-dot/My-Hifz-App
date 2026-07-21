import 'package:shared_preferences/shared_preferences.dart';

enum ArabicFontSize { small, medium, large }

class SettingsService {
  SettingsService._internal();
  static final SettingsService instance = SettingsService._internal();

  static const _keyFontSize = 'arabic_font_size';
  static const _keyDarkMode = 'dark_mode';
  static const _keyReferenceAudioEnabled = 'reference_audio_enabled';
  static const _keyLastSurah = 'last_surah';
  static const _keyLastAyah = 'last_ayah';
  static const _keyRecognitionEndpoint = 'recognition_endpoint_url';
  static const _keyInterruptionCueEnabled = 'interruption_cue_enabled';

  Future<String> getRecognitionEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRecognitionEndpoint) ?? '';
  }

  Future<void> setRecognitionEndpoint(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRecognitionEndpoint, url);
  }

  Future<bool> getInterruptionCueEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyInterruptionCueEnabled) ?? true;
  }

  Future<void> setInterruptionCueEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInterruptionCueEnabled, enabled);
  }

  Future<ArabicFontSize> getFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyFontSize) ?? 'medium';
    return ArabicFontSize.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ArabicFontSize.medium,
    );
  }

  Future<void> setFontSize(ArabicFontSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontSize, size.name);
  }

  Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? false;
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, enabled);
  }

  Future<bool> getReferenceAudioEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReferenceAudioEnabled) ?? false;
  }

  Future<void> setReferenceAudioEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReferenceAudioEnabled, enabled);
  }

  Future<void> setLastSession(int surah, int ayah) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSurah, surah);
    await prefs.setInt(_keyLastAyah, ayah);
  }

  /// Returns (surah, ayah) of the last session, or null if there isn't one.
  Future<(int, int)?> getLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    final surah = prefs.getInt(_keyLastSurah);
    final ayah = prefs.getInt(_keyLastAyah);
    if (surah == null || ayah == null) return null;
    return (surah, ayah);
  }
}
