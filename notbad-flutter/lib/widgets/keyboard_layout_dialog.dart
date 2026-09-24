import 'package:flutter/material.dart';
import '../theme.dart';

/// Interactive visual reference dialog for the Anu Script / Apple Telugu keyboard layout.
class KeyboardLayoutDialog extends StatelessWidget {
  final TracePalette palette;

  const KeyboardLayoutDialog({super.key, required this.palette});

  static Future<void> show(BuildContext context, TracePalette palette) {
    return showDialog<void>(
      context: context,
      builder: (context) => KeyboardLayoutDialog(palette: palette),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: palette.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: palette.accent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'తె (అను)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: palette.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Anu Script / Apple Telugu Keyboard Layout',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: palette.fg,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: palette.muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Visual Keyboard
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.sidebarBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      children: [
                        _buildRow(_row1),
                        const SizedBox(height: 6),
                        _buildRow(_row2),
                        const SizedBox(height: 6),
                        _buildRow(_row3),
                        const SizedBox(height: 6),
                        _buildRow(_row4),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Guide & Tips
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.codeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Typing Rules & Guninthalu (Matras):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: palette.fg,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          _tipItem('Vowels / Matras:',
                              'e=ా, r=ి, w=ీ, i=ు, p=ూ, u=ె, o=ే, t=ొ, y=ో, ]=ౌ'),
                          _tipItem('Halant / Otthu:', 'h key (e.g. j + h + j = క్క)'),
                          _tipItem('Anusvara / Visarga:', 'g = ం (అనుస్వార), G (Shift+G) = ః'),
                          _tipItem('Special Ligatures:', 'Y (Shift+Y) = క్ష, U (Shift+U) = శ్రీ'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tipItem(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: palette.accent,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 11.5,
              color: palette.fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<_KeyInfo> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final k in keys) ...[
          _buildKey(k),
          const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildKey(_KeyInfo k) {
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: palette.toolbarBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top: Shift character + Latin key name
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  k.shift,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: palette.accent,
                    fontFamilyFallback: const ['Noto Sans Telugu', 'Gautami'],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                k.latin,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: palette.muted,
                ),
              ),
            ],
          ),
          // Bottom: Normal character
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              k.normal,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.fg,
                fontFamilyFallback: const ['Noto Sans Telugu', 'Gautami'],
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<_KeyInfo> _row1 = [
    _KeyInfo('1', '1', '_'),
    _KeyInfo('2', '2', "'"),
    _KeyInfo('3', '3', '%'),
    _KeyInfo('4', '4', '౨'),
    _KeyInfo('5', '5', '('),
    _KeyInfo('6', '6', '-'),
    _KeyInfo('7', '7', '1'),
    _KeyInfo('8', '8', "'"),
    _KeyInfo('9', '9', '('),
    _KeyInfo('0', '0', ')'),
    _KeyInfo('-', '×', '÷'),
    _KeyInfo('=', '=', '+'),
  ];

  static const List<_KeyInfo> _row2 = [
    _KeyInfo('Q', 'అ', 'క్ష్మి'),
    _KeyInfo('W', 'ఈ', 'ౠ'),
    _KeyInfo('E', 'ఆ', 'ఋ'),
    _KeyInfo('R', 'ఇ', 'ఙ'),
    _KeyInfo('T', 'ఒ', 'ఞ'),
    _KeyInfo('Y', 'ఓ', 'క్ష'),
    _KeyInfo('U', 'ఎ', 'శ్రీ'),
    _KeyInfo('I', 'ఉ', 'డ'),
    _KeyInfo('O', 'ఏ', 'ర్'),
    _KeyInfo('P', 'ఊ', 'కృ'),
    _KeyInfo('[', 'ఱ', 'క్ష్మ'),
    _KeyInfo(']', 'ఔ', '!'),
  ];

  static const List<_KeyInfo> _row3 = [
    _KeyInfo('A', 'ల', 'ళ'),
    _KeyInfo('S', 'త', 'థ'),
    _KeyInfo('D', 'ద', 'ధ'),
    _KeyInfo('F', 'ప', 'ఫ'),
    _KeyInfo('G', 'ం', 'ః'),
    _KeyInfo('H', '్', '↔'),
    _KeyInfo('J', 'క', 'ఖ'),
    _KeyInfo('K', 'ర', 'ల'),
    _KeyInfo('L', 'స', 'ణ'),
    _KeyInfo(';', 'వ', 'శ'),
    _KeyInfo("'", 'న', 'ష'),
  ];

  static const List<_KeyInfo> _row4 = [
    _KeyInfo('Z', 'ట', 'ఠ'),
    _KeyInfo('X', 'గ', 'ఘ'),
    _KeyInfo('C', 'డ', 'ఢ'),
    _KeyInfo('V', 'బ', 'భ'),
    _KeyInfo('B', 'మ', 'హ'),
    _KeyInfo('N', 'య', 'క్ష'),
    _KeyInfo('M', 'చ', 'ఛ'),
    _KeyInfo(',', ',', ';'),
    _KeyInfo('.', '.', '?'),
    _KeyInfo('/', 'జ', 'ఝ'),
  ];
}

class _KeyInfo {
  final String latin;
  final String normal;
  final String shift;
  const _KeyInfo(this.latin, this.normal, this.shift);
}
