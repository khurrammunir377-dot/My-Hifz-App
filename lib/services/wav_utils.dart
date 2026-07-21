import 'dart:typed_data';

/// Wraps raw 16-bit PCM audio bytes with a standard WAV header, since the
/// record package's streaming API (startStream) yields raw PCM data with no
/// container - both the backend transcription API and local playback expect
/// a properly-headed WAV file.
Uint8List pcm16ToWav({
  required List<int> pcmBytes,
  required int sampleRate,
  required int numChannels,
}) {
  final byteRate = sampleRate * numChannels * 2; // 16-bit = 2 bytes/sample
  final blockAlign = numChannels * 2;
  final dataLength = pcmBytes.length;
  final fileLength = 36 + dataLength;

  final header = BytesBuilder();
  header.add('RIFF'.codeUnits);
  header.add(_int32le(fileLength));
  header.add('WAVE'.codeUnits);
  header.add('fmt '.codeUnits);
  header.add(_int32le(16)); // fmt chunk size
  header.add(_int16le(1)); // PCM format
  header.add(_int16le(numChannels));
  header.add(_int32le(sampleRate));
  header.add(_int32le(byteRate));
  header.add(_int16le(blockAlign));
  header.add(_int16le(16)); // bits per sample
  header.add('data'.codeUnits);
  header.add(_int32le(dataLength));
  header.add(pcmBytes);

  return header.toBytes();
}

List<int> _int32le(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

List<int> _int16le(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
    ];
