import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
  bool _isLoading = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isLoading) {
      return;
    }
    if (_isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      final wave = await compute(
        createMusicWaveFromData,
        [
          for (final note in widget.notes)
            [note.delay, note.duration, note.frequency],
        ],
      );
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await _player.play(BytesSource(wave, mimeType: 'audio/wav'));
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('MUSIC PLAYBACK FAILED: $error')),
        );
      }
    }
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
          style: IconButton.styleFrom(
            backgroundColor: Colors.limeAccent.shade400,
            foregroundColor: Colors.black,
          ),
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2,
                  ),
                )
              : Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          tooltip: _isLoading
              ? 'LOADING MUSIC'
              : _isPlaying
              ? 'STOP MUSIC'
              : 'PLAY MUSIC',
          onPressed: _isLoading ? null : _togglePlayback,
        ),
        const SizedBox(width: 8),
        Text('MUSIC: ${widget.notes.length} NOTES'),
      ],
    );
  }
}

Uint8List createMusicWave(List<MusicNote> notes) {
  const sampleRate = 44100;
  final duration = notes
      .map((note) => note.delay + note.duration)
      .reduce(math.max)
      .clamp(0, 10 * 60)
      .toDouble();
  final sampleCount = (duration * sampleRate).ceil();
  final bytes = ByteData(44 + sampleCount * 2);
  _writeWaveHeader(bytes, sampleCount, sampleRate);

  final amplitudes = Float64List(sampleCount);
  final activeNotes = Uint16List(sampleCount);
  for (final note in notes) {
    final firstSample = (note.delay * sampleRate).ceil().clamp(0, sampleCount);
    final lastSample = ((note.delay + note.duration) * sampleRate)
        .ceil()
        .clamp(0, sampleCount);
    for (var sampleIndex = firstSample; sampleIndex < lastSample; sampleIndex++) {
      final time = sampleIndex / sampleRate - note.delay;
      final phase = 2 * math.pi * note.frequency * time;
      amplitudes[sampleIndex] +=
          (math.sin(phase) + .5 * math.sin(2 * phase) + .25 * math.sin(3 * phase)) /
          1.75;
      activeNotes[sampleIndex]++;
    }
  }

  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final sample = activeNotes[sampleIndex] == 0
        ? 0
        : (amplitudes[sampleIndex] / activeNotes[sampleIndex] * 0x5fff)
            .round()
            .clamp(-0x8000, 0x7fff);
    bytes.setInt16(44 + sampleIndex * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List createMusicWaveFromData(List<List<double>> noteData) {
  return createMusicWave([
    for (final values in noteData)
      MusicNote(
        delay: values[0],
        duration: values[1],
        frequency: values[2],
      ),
  ]);
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