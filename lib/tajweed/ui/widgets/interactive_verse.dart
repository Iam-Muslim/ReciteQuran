import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/word_model.dart';
import '../../utils/text_helper.dart';

List<TextSpan> buildHighlightedWordSpans({
  required WordModel word,
  required bool isSelected,
  TapGestureRecognizer? recognizer,
  bool appendSpace = false,
  double fontSize = 28,
}) {
  final spans = <TextSpan>[];

  if (!word.hasError) {
    spans.add(
      TextSpan(
        text: '${word.text}${appendSpace ? ' ' : ''}',
        style: TextStyle(
          fontFamily: 'HafsSmart',
          fontSize: fontSize,
          color: isSelected ? Colors.blue : const Color(0xFF1E293B),
          backgroundColor: isSelected
              ? Colors.blue.withValues(alpha: 0.1)
              : Colors.transparent,
          height: 1.8,
        ),
        recognizer: recognizer,
      ),
    );
    return spans;
  }

  // Uthmani text gets full word highlighting in the main verse view
  spans.add(
    TextSpan(
      text: '${word.text}${appendSpace ? ' ' : ''}',
      style: TextStyle(
        fontFamily: 'HafsSmart',
        fontSize: fontSize,
        color: Colors.red,
        backgroundColor: Colors.red.withValues(alpha: 0.15),
        height: 1.8,
      ),
      recognizer: recognizer,
    ),
  );

  return spans;
}

// ─── Ported 1:1 from ResultsView.swift arabicSifaName() ────────────────────
// ─── InteractiveVerse ────────────────────────────────────────────────────────

// Widget responsible for rendering the Quran verse dynamically with interactive tajweed errors.
class InteractiveVerse extends StatefulWidget {
  final List<WordModel> words;
  final ValueChanged<WordModel?>? onWordSelected;

  const InteractiveVerse({super.key, required this.words, this.onWordSelected});

  @override
  State<InteractiveVerse> createState() => _InteractiveVerseState();
}

class _InteractiveVerseState extends State<InteractiveVerse> {
  int? _selectedWordIndex;
  late List<TapGestureRecognizer> _recognizers;

  @override
  void initState() {
    super.initState();
    _initRecognizers();
  }

  void _initRecognizers() {
    _recognizers = List.generate(
      widget.words.length,
      (index) => TapGestureRecognizer()..onTap = () => _handleWordTap(index),
    );
  }

  @override
  void didUpdateWidget(InteractiveVerse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.words.length != oldWidget.words.length) {
      _disposeRecognizers();
      _initRecognizers();
      _selectedWordIndex = null;
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (var r in _recognizers) {
      r.dispose();
    }
  }

  void _handleWordTap(int index) {
    HapticFeedback.lightImpact();

    setState(() {
      _selectedWordIndex = (_selectedWordIndex == index) ? null : index;
    });

    if (widget.onWordSelected != null) {
      widget.onWordSelected!(
        _selectedWordIndex != null ? widget.words[_selectedWordIndex!] : null,
      );
    }

    if (_selectedWordIndex != null) {
      final word = widget.words[_selectedWordIndex!];
      if (word.sifatErrors.isNotEmpty) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) =>
              WordErrorsSheet(word: word, allWords: widget.words),
        ).whenComplete(() {
          setState(() => _selectedWordIndex = null);
          if (widget.onWordSelected != null) {
            widget.onWordSelected!(null);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];

    for (int index = 0; index < widget.words.length; index++) {
      final word = widget.words[index];
      final isSelected = _selectedWordIndex == index;

      spans.addAll(
        buildHighlightedWordSpans(
          word: word,
          isSelected: isSelected,
          recognizer: _recognizers[index],
          appendSpace: true,
          fontSize: 28,
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(children: spans),
      ),
    );
  }
}

// ─── WordErrorsSheet ─────────────────────────────────────────────────────────

class WordErrorsSheet extends StatefulWidget {
  final WordModel word;
  final List<WordModel> allWords;

  const WordErrorsSheet({
    super.key,
    required this.word,
    required this.allWords,
  });

  @override
  State<WordErrorsSheet> createState() => _WordErrorsSheetState();
}

class _WordErrorsSheetState extends State<WordErrorsSheet> {
  late AudioPlayer _audioPlayer;
  final ScrollController scrollController = ScrollController();
  bool _isPlaying = false;
  int? selectedPhonemeIndex;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });

    _audioPlayer.onPositionChanged.listen((pos) async {
      if (_isPlaying) {
        final duration = await _audioPlayer.getDuration();
        final durationMs = duration?.inMilliseconds.toDouble() ?? 0;

        final wordIndex = widget.word.index;
        // Use next word's end if available, else current word's end + 1 second, clamped to duration
        double targetEnd =
            widget.word.endMs ?? (durationMs * widget.word.endFraction);
        if (wordIndex < widget.allWords.length - 1) {
          targetEnd =
              widget.allWords[wordIndex + 1].endMs ?? (targetEnd + 1000);
        } else {
          targetEnd += 500; // Add a little buffer if it's the last word
        }

        if (pos.inMilliseconds >= targetEnd) {
          _audioPlayer.pause();
          if (mounted) setState(() => _isPlaying = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/recitation.wav';
      if (await File(filePath).exists()) {
        await _audioPlayer.setSource(DeviceFileSource(filePath));
        final duration = await _audioPlayer.getDuration();
        final durationMs = duration?.inMilliseconds.toDouble() ?? 0;

        final wordIndex = widget.word.index;
        // Start from previous word's start time if available
        double targetStart =
            widget.word.startMs ?? (durationMs * widget.word.startFraction);
        if (wordIndex > 0) {
          targetStart =
              widget.allWords[wordIndex - 1].startMs ?? (targetStart - 1000);
          if (targetStart < 0) targetStart = 0;
        }

        double targetEnd =
            widget.word.endMs ?? (durationMs * widget.word.endFraction);
        if (wordIndex < widget.allWords.length - 1) {
          targetEnd =
              widget.allWords[wordIndex + 1].endMs ?? (targetEnd + 1000);
        } else {
          targetEnd += 500;
        }

        debugPrint(
          "🎵 Playing audio context: startMs=$targetStart, endMs=$targetEnd",
        );

        await _audioPlayer.play(
          DeviceFileSource(filePath),
          position: Duration(milliseconds: targetStart.toInt()),
        );
      }
    }
  }

  List<String> getCharMappings(String baseChar) {
    final mappings = <String, List<String>>{
      // Hamza variants
      "ء": ["أ", "إ", "آ", "ؤ", "ئ", "ٱ"],
      "أ": ["ء", "إ", "آ", "ٱ"],
      "إ": ["ء", "أ", "آ", "ٱ"],
      // Alef variants
      "ا": ["آ", "أ", "إ", "ٰ", "ى", "ٱ", "ـٰ"],
      "ٱ": ["ا", "آ", "أ", "إ"],
      "ٰ": ["ا"],
      "ـٰ": ["ا"],
      // Ha/Ta marbuta
      "ه": ["ة", "ھ"],
      "ة": ["ه"],
      // Yaa variants
      "ي": ["ى", "ۦ", "ئ", "ی"],
      "ى": ["ي", "ۦ"],
      "ۦ": ["ي", "ى", "ئ"],
      // Waw variants
      "و": ["ۥ", "ؤ"],
      "ۥ": ["و", "ؤ"],
      // Common substitutions
      "ن": ["ں"],
      "ر": ["ڔ"],
      "ل": ["ڵ"],
      "ك": ["ک"],
    };

    final result = <String>{};
    if (mappings.containsKey(baseChar)) {
      result.addAll(mappings[baseChar]!);
    }

    for (int i = 0; i < baseChar.length; i++) {
      final c = baseChar[i];
      if (mappings.containsKey(c)) {
        result.addAll(mappings[c]!);
      }
    }

    return result.toList();
  }

  List<TextSpan> _buildInteractiveWordSpans() {
    final spans = <TextSpan>[];
    final phonemeGroups = _groupErrorsByPhoneme(widget.word.sifatErrors);
    
    if (selectedPhonemeIndex == null || selectedPhonemeIndex! >= phonemeGroups.length) {
      // Return default word with no highlights
      return [
        TextSpan(
          text: widget.word.text,
          style: const TextStyle(
            fontFamily: 'HafsSmart',
            fontSize: 48,
            color: Color(0xFF1E293B),
            height: 1.8,
          ),
        )
      ];
    }

    final selectedGroup = phonemeGroups[selectedPhonemeIndex!];
    final originalPhoneme = selectedGroup.phoneme;
    
    final phonemeBase = stripArabicDiacritics(originalPhoneme);
    final uniqueChars = phonemeBase.split('').toSet();
    final targetBase = (uniqueChars.length == 1 && phonemeBase.isNotEmpty)
        ? uniqueChars.first
        : phonemeBase;
        
    final charactersList = widget.word.text.characters.toList();

    for (int i = 0; i < charactersList.length; i++) {
      final charStr = charactersList[i];
      final charBase = stripArabicDiacritics(charStr);

      bool isMatch = false;

      if (charBase.isNotEmpty && targetBase.isNotEmpty) {
        final mappings = getCharMappings(targetBase);

        if (charBase == targetBase ||
            mappings.contains(charBase) ||
            (targetBase.contains(charBase) &&
                targetBase.length > charBase.length)) {
          isMatch = true;
        }
      }

      spans.add(
        TextSpan(
          text: charStr,
          style: TextStyle(
            fontFamily: 'HafsSmart',
            fontSize: 48,
            color: isMatch ? Colors.red : const Color(0xFF1E293B),
            backgroundColor: isMatch ? Colors.red.withValues(alpha: 0.15) : Colors.transparent,
            height: 1.8,
          ),
        ),
      );
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Word text & Error Count
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Audio button
                  Material(
                    color: _isPlaying
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.red,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _toggleAudio,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          _isPlaying ? Icons.stop : Icons.volume_up,
                          color: _isPlaying ? Colors.red : Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Error count badge
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${widget.word.sifatErrors.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Word itself (Highlighted with letters)
                  RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      children: _buildInteractiveWordSpans(),
                      style: const TextStyle(
                        fontFamily: 'HafsSmart',
                        fontSize: 48,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Errors list grouped by phoneme, displayed vertically
              Builder(
                builder: (context) {
                  final groups = _groupErrorsByPhoneme(widget.word.sifatErrors);
                  return Column(
                    children: groups.asMap().entries.map((entry) {
                      final index = entry.key;
                      final group = entry.value;
                      final isSelected = selectedPhonemeIndex == index;
                      
                      return PhonemeGroupButton(
                        group: group,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            if (selectedPhonemeIndex == index) {
                              selectedPhonemeIndex = null;
                            } else {
                              selectedPhonemeIndex = index;
                            }
                          });
                        },
                      );
                    }).toList(),
                  );
                }
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_PhonemeGroup> _groupErrorsByPhoneme(List<TajweedError> errors) {
    final Map<String, List<TajweedError>> groups = {};
    final List<String> order = [];

    // Sort errors by their exact character index
    final sortedErrors = List<TajweedError>.from(errors)
      ..sort((a, b) {
        int idxA = a.charIndex ?? 999;
        int idxB = b.charIndex ?? 999;

        // Fallback if charIndex is not available
        if (idxA == 999) {
          final baseA = stripArabicDiacritics(a.expectedPhoneme);
          if (baseA.isNotEmpty) idxA = widget.word.cleanText.indexOf(baseA[0]);
          if (idxA == -1 && a.expectedPhoneme.isNotEmpty) {
            idxA = widget.word.cleanText.indexOf(a.expectedPhoneme[0]);
          }
          if (idxA == -1) idxA = 999;
        }

        if (idxB == 999) {
          final baseB = stripArabicDiacritics(b.expectedPhoneme);
          if (baseB.isNotEmpty) idxB = widget.word.cleanText.indexOf(baseB[0]);
          if (idxB == -1 && b.expectedPhoneme.isNotEmpty) {
            idxB = widget.word.cleanText.indexOf(b.expectedPhoneme[0]);
          }
          if (idxB == -1) idxB = 999;
        }

        return idxA.compareTo(idxB);
      });

    for (final error in sortedErrors) {
      if (!groups.containsKey(error.phoneme)) {
        order.add(error.phoneme);
        groups[error.phoneme] = [];
      }
      groups[error.phoneme]!.add(error);
    }

    return order
        .map(
          (phoneme) =>
              _PhonemeGroup(phoneme: phoneme, errors: groups[phoneme]!),
        )
        .toList();
  }
}

        )
        .toList();
  }
}

class _PhonemeGroup {
  final String phoneme;
  final List<TajweedError> errors;
  _PhonemeGroup({required this.phoneme, required this.errors});
}

class PhonemeGroupButton extends StatelessWidget {
  final _PhonemeGroup group;
  final bool isSelected;
  final VoidCallback onTap;

  const PhonemeGroupButton({
    required this.group,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.red.withValues(alpha: 0.1) : Colors.clear,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: TextDirection.rtl,
            children: [
              // Header row: selection indicator and phoneme
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.red : Colors.grey,
                    size: 20,
                  ),
                  const Spacer(),
                  Text(
                    group.phoneme,
                    style: TextStyle(
                      fontFamily: 'HafsSmart',
                      fontSize: 24,
                      color: isSelected ? Colors.red : const Color(0xFF1E293B),
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
              
              // Always show all errors vertically
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: TextDirection.rtl,
                children: group.errors.map((error) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          error.expected,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.green,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_back,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          error.actual,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}