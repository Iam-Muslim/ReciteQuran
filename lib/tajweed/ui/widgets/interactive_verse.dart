import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/app_state.dart';
import '../../models/muaalem_result.dart';
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
          color: isSelected ? Colors.blue : AppState.instance.colors.text,
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
      if (word.sifatList.isNotEmpty) {
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
        double targetEnd =
            widget.word.endMs ?? (durationMs * widget.word.endFraction);
        if (wordIndex < widget.allWords.length - 1) {
          targetEnd =
              widget.allWords[wordIndex + 1].endMs ?? (targetEnd + 1000);
        } else {
          targetEnd += 500;
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
      "ء": ["أ", "إ", "آ", "ؤ", "ئ", "ٱ"],
      "أ": ["ء", "إ", "آ", "ٱ"],
      "إ": ["ء", "أ", "آ", "ٱ"],
      "ا": ["آ", "أ", "إ", "ٰ", "ى", "ٱ", "ـٰ"],
      "ٱ": ["ا", "آ", "أ", "إ"],
      "ٰ": ["ا"],
      "ـٰ": ["ا"],
      "ه": ["ة", "ھ"],
      "ة": ["ه"],
      "ي": ["ى", "ۦ", "ئ", "ی"],
      "ى": ["ي", "ۦ"],
      "ۦ": ["ي", "ى", "ئ"],
      "و": ["ۥ", "ؤ"],
      "ۥ": ["و", "ؤ"],
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
    final sifatList = widget.word.sifatList;

    if (selectedPhonemeIndex == null ||
        selectedPhonemeIndex! >= sifatList.length) {
      return [
        TextSpan(
          text: widget.word.text,
          style: const TextStyle(
            fontFamily: 'HafsSmart',
            fontSize: 48,
            color: Color(0xFF1E293B),
            height: 1.8,
          ),
        ),
      ];
    }

    final selectedGroup = sifatList[selectedPhonemeIndex!];
    final originalPhoneme = selectedGroup.phonemesGroup;

    String normalizeChar(String c) {
      var s = stripArabicDiacritics(c).trim();
      s = s.replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202c\u200b]'), '');
      s = s.replaceAll(RegExp(r'[ٱآأإٰ]'), 'ا');
      s = s.replaceAll('ـٰ', 'ا');
      s = s.replaceAll(RegExp(r'[ىئۦيـی]'), 'ي');
      s = s.replaceAll(RegExp(r'[ؤۥ]'), 'و');
      s = s.replaceAll('ة', 'ه');
      s = s.replaceAll('ء', 'ا');
      s = s.replaceAll('ـ', '');
      return s;
    }

    final phonemeBase = normalizeChar(originalPhoneme);
    final uniqueChars = phonemeBase.split('').toSet();
    final targetBase = (uniqueChars.length == 1 && phonemeBase.isNotEmpty)
        ? uniqueChars.first
        : phonemeBase;

    final fullText = widget.word.text;
    final chars = fullText.characters.toList();

    List<bool> isHighlighted = List.filled(chars.length, false);
    bool foundMatch = false;

    for (int i = 0; i < chars.length; i++) {
      final charStr = chars[i];
      final charBase = normalizeChar(charStr);

      if (charBase.isNotEmpty && targetBase.isNotEmpty) {
        final mappings = getCharMappings(targetBase);

        if (charBase == targetBase ||
            mappings.contains(charBase) ||
            (targetBase.contains(charBase) &&
                targetBase.length > charBase.length)) {
          isHighlighted[i] = true;
          foundMatch = true;

          int j = i + 1;
          while (j < chars.length && normalizeChar(chars[j]).isEmpty) {
            isHighlighted[j] = true;
            j++;
          }
          i = j - 1;
        }
      }
    }

    // Mathematical Fallback based on relative position if no match found
    if (!foundMatch && chars.isNotEmpty) {
      double frac = selectedPhonemeIndex! / sifatList.length;
      int charIdx = (chars.length * frac).floor().clamp(0, chars.length - 1);

      // Find nearest non-empty base char
      int bestIdx = charIdx;
      for (int i = 0; i < chars.length; i++) {
        int left = charIdx - i;
        int right = charIdx + i;
        if (left >= 0 && normalizeChar(chars[left]).isNotEmpty) {
          bestIdx = left;
          break;
        }
        if (right < chars.length && normalizeChar(chars[right]).isNotEmpty) {
          bestIdx = right;
          break;
        }
      }

      isHighlighted[bestIdx] = true;
      foundMatch = true;

      int j = bestIdx + 1;
      while (j < chars.length && normalizeChar(chars[j]).isEmpty) {
        isHighlighted[j] = true;
        j++;
      }
    }

    String currentText = "";
    bool currentStyle = false;
    bool first = true;

    for (int i = 0; i < chars.length; i++) {
      final highlight = isHighlighted[i];
      if (first) {
        currentStyle = highlight;
        currentText = chars[i];
        first = false;
      } else if (currentStyle == highlight) {
        currentText += chars[i];
      } else {
        spans.add(
          TextSpan(
            text: currentText,
            style: TextStyle(
              fontFamily: 'HafsSmart',
              fontSize: 48,
              color: currentStyle ? Colors.white : const Color(0xFF1E293B),
              backgroundColor: currentStyle
                  ? Colors.blueAccent
                  : Colors
                        .transparent, // Use blue instead of red since it's just selection
              height: 1.8,
            ),
          ),
        );
        currentStyle = highlight;
        currentText = chars[i];
      }
    }

    if (currentText.isNotEmpty) {
      spans.add(
        TextSpan(
          text: currentText,
          style: TextStyle(
            fontFamily: 'HafsSmart',
            fontSize: 48,
            color: currentStyle ? Colors.white : const Color(0xFF1E293B),
            backgroundColor: currentStyle
                ? Colors.blueAccent
                : Colors.transparent,
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

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Material(
                    color: _isPlaying
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.blue,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _toggleAudio,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          _isPlaying ? Icons.stop : Icons.volume_up,
                          color: _isPlaying ? Colors.blue : Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  RichText(
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
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

              Builder(
                builder: (context) {
                  return Column(
                    children: widget.word.sifatList.asMap().entries.map((
                      entry,
                    ) {
                      final index = entry.key;
                      final sifa = entry.value;
                      final isSelected = selectedPhonemeIndex == index;

                      return PhonemeGroupButton(
                        sifa: sifa,
                        isSelected: isSelected,
                        cleanWord: widget.word.cleanText,
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
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhonemeGroupButton extends StatelessWidget {
  final SifaItem sifa;
  final bool isSelected;
  final VoidCallback onTap;
  final String cleanWord;

  const PhonemeGroupButton({
    super.key,
    required this.sifa,
    required this.isSelected,
    required this.onTap,
    required this.cleanWord,
  });

  @override
  Widget build(BuildContext context) {
    // Collect all valid attributes
    final attributes = <String>[];

    void addAttr(SingleUnit? unit) {
      if (unit != null &&
          unit.text.isNotEmpty &&
          unit.text != '[PAD]' &&
          unit.text != 'none' &&
          unit.text != 'false') {
        final translated = translateSifa(unit.text);
        if (translated != 'غير واضح' && translated != 'لا يوجد') {
          attributes.add(translated);
        }
      }
    }

    addAttr(sifa.hamsOrJahr);
    addAttr(sifa.shiddaOrRakhawa);
    addAttr(sifa.tafkheemOrTaqeeq);
    addAttr(sifa.itbaq);
    addAttr(sifa.safeer);
    addAttr(sifa.qalqla);
    addAttr(sifa.tikraar);
    addAttr(sifa.tafashie);
    addAttr(sifa.istitala);
    addAttr(sifa.ghonna);

    final bool isError = sifa.phonemeProb < 0.85;
    final MaterialColor themeColor = isError ? Colors.red : Colors.blue;

    String displayChar = sifa.phonemesGroup;
    if (sifa.charIndex >= 0 && sifa.charIndex < cleanWord.length) {
      final actualChar = cleanWord[sifa.charIndex];
      // Note: we can show actual character if they differ substantially
      displayChar = actualChar;
      if (isError &&
          sifa.phonemesGroup != actualChar &&
          sifa.phonemesGroup.isNotEmpty &&
          !['ي', 'و', 'ا'].contains(sifa.phonemesGroup)) {
        displayChar = '$actualChar (نُطقت: ${sifa.phonemesGroup})';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: themeColor.withValues(alpha: 0.1),
          highlightColor: themeColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        themeColor.withValues(alpha: 0.08),
                        themeColor.withValues(alpha: 0.02),
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    )
                  : const LinearGradient(
                      colors: [Colors.transparent, Colors.transparent],
                    ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? themeColor.withValues(alpha: 0.4)
                    : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: TextDirection.rtl,
              children: [
                // Header row: selection indicator and phoneme
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Text(
                      displayChar,
                      style: TextStyle(
                        fontFamily: 'HafsSmart',
                        fontSize: 28, // Slightly larger for modern look
                        color: isSelected
                            ? themeColor
                            : (isError ? Colors.red : const Color(0xFF1E293B)),
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(isSelected),
                        color: isSelected
                            ? themeColor
                            : Colors.grey.withValues(alpha: 0.5),
                        size: 24,
                      ),
                    ),
                  ],
                ),

                // Show attributes in a wrap
                if (attributes.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        textDirection: TextDirection.rtl,
                        spacing: 8,
                        runSpacing: 8,
                        children: attributes.map((attr) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: themeColor.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              attr,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isError
                                    ? Colors.red.shade700
                                    : Colors.blueGrey,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
