import 'package:flutter/material.dart';
import '../../../state/app_state.dart';
import 'setting_tile.dart';

/// Font size slider tile with live Arabic preview markers.
class FontSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const FontSliderTile({
    super.key,
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<FontSliderTile> createState() => _FontSliderTileState();
}

class _FontSliderTileState extends State<FontSliderTile> {
  late double _localSize;

  @override
  void initState() {
    super.initState();
    _localSize = widget.app.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isAr = widget.isAr;

    return SettingTile(
      icon: Icons.format_size_rounded,
      title: isAr ? 'حجم الخط' : 'Font Size',
      c: c,
      trailing: Row(
        children: [
          Text(
            'أ',
            style: TextStyle(
              fontFamily: 'HafsSmart',
              color: c.muted,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
                trackHeight: 4,
                activeTrackColor: c.gold,
                inactiveTrackColor: c.border.withValues(alpha: 0.5),
                thumbColor: c.gold,
                overlayColor: c.gold.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: _localSize,
                min: 16.0,
                max: 42.0,
                onChanged: (v) {
                  setState(() => _localSize = v);
                },
                onChangeEnd: (v) {
                  app.setFontSize(v);
                },
              ),
            ),
          ),
          Text(
            'أ',
            style: TextStyle(
              fontFamily: 'HafsSmart',
              color: c.muted,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}
