import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class AyahPlayer extends StatefulWidget {
  final int sura;
  final int aya;

  const AyahPlayer({super.key, required this.sura, required this.aya});

  @override
  State<AyahPlayer> createState() => _AyahPlayerState();
}

class _AyahPlayerState extends State<AyahPlayer> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (_isPlaying) _isLoading = false;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AyahPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sura != widget.sura || oldWidget.aya != widget.aya) {
      _audioPlayer.stop();
      setState(() {
        _isPlaying = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      setState(() => _isLoading = true);
      try {
        final suraStr = widget.sura.toString().padLeft(3, '0');
        final ayaStr = widget.aya.toString().padLeft(3, '0');
        final url =
            'https://everyayah.com/data/Husary_64kbps/$suraStr$ayaStr.mp3';

        await _audioPlayer.play(UrlSource(url));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('فشل تشغيل الصوت: $e')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _isPlaying
          ? Colors.blue.withValues(alpha: 0.1)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: _isPlaying ? Colors.blue : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        onTap: _toggleAudio,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: _isPlaying ? Colors.blue : Colors.black87,
                      size: 20,
                    ),
              const SizedBox(width: 8),
              Text(
                'استماع للآية',
                style: TextStyle(
                  color: _isPlaying ? Colors.blue : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
