import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class AyahPlayer extends StatefulWidget {
  final int sura;
  final int aya;
  final bool compact;

  const AyahPlayer({
    super.key,
    required this.sura,
    required this.aya,
    this.compact = false,
  });

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
      await _audioPlayer.stop(); // Stop instead of pause to reset position
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
    // We import AppState globally to use theme colors, but for this small widget
    // we can rely on standard context colors or just use the app's standard gold.
    // Assuming standard blue/grey if we don't import app_state here, but the user requested a modern look.
    final color = _isPlaying ? Colors.red : const Color(0xFFD4AF37); // Gold

    return Material(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: _toggleAudio,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 16,
            vertical: widget.compact ? 6 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isLoading
                  ? SizedBox(
                      width: widget.compact ? 14 : 20,
                      height: widget.compact ? 14 : 20,
                      child: CircularProgressIndicator(
                        strokeWidth: widget.compact ? 1.5 : 2,
                        color: color,
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: color,
                      size: widget.compact ? 16 : 20,
                    ),
              SizedBox(width: widget.compact ? 4 : 8),
              Text(
                'استماع للآية',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: widget.compact ? 11 : 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
