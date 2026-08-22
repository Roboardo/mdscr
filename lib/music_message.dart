import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'signal_dictionary.dart';

class MusicMessage extends StatefulWidget {
  const MusicMessage({super.key, required this.notes});

  final List<MusicNote> notes;

  @override
  State<MusicMessage> createState() => _MusicMessageState();
}

class _MusicMessageState extends State<MusicMessage> {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    setState(() => _isPlaying = true);
    await _player.play(BytesSource(_createWave(widget.notes)));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          tooltip: _isPlaying ? 'STOP MUSIC' : 'PLAY MUSIC',
          onPressed: _togglePlayback,
        ),
        const SizedBox(width: 8),
        Text('MUSIC: ${widget.notes.length} NOTES'),
      ],
    );
  }
}

Uint8List _createWave(List<MusicNote> notes) {
  const sampleRate = 44100;
  final duration = notes
      .map((note) => note.delay + note.duration)
      .reduce(math.max)
      .clamp(0, 60)
      .toDouble();
  final sampleCount = (duration * sampleRate).ceil();
  final bytes = ByteData(44 + sampleCount * 2);
  _writeWaveHeader(bytes, sampleCount, sampleRate);

  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final time = sampleIndex / sampleRate;
    var amplitude = 0.0;
    var activeNotes = 0;
    for (final note in notes) {
      if (time >= note.delay && time < note.delay + note.duration) {
        amplitude += math.sin(2 * math.pi * note.frequency * (time - note.delay));
        activeNotes++;
      }
    }
    final sample = activeNotes == 0
        ? 0
        : (amplitude / activeNotes * 0x5fff).round().clamp(-0x8000, 0x7fff);
    bytes.setInt16(44 + sampleIndex * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void _writeWaveHeader(ByteData bytes, int sampleCount, int sampleRate) {
  final dataLength = sampleCount * 2;
  void writeText(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  writeText(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeText(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeText(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
}