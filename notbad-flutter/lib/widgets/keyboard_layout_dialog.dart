import 'package:flutter/material.dart';
import '../input_methods/indic_engine.dart';
import '../theme.dart';

/// Interactive visual keyboard and reference dialog for the Anu Script / Apple Telugu layout.
class KeyboardLayoutDialog extends StatefulWidget {
  final TracePalette palette;
  final void Function(String text)? onKeyTap;

  const KeyboardLayoutDialog({
    super.key,
    required this.palette,
    this.onKeyTap,
  });

  static Future<void> show(
    BuildContext context,
    TracePalette palette, {
    void Function(String text)? onKeyTap,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => KeyboardLayoutDialog(
        palette: palette,
        onKeyTap: onKeyTap,
      ),
    );
  }

  @override
  State<KeyboardLayoutDialog> createState() => _KeyboardLayoutDialogState();
}

class _KeyboardLayoutDialogState extends State<KeyboardLayoutDialog> {
  bool _shiftMode = false;
  String? _lastInserted;

  TracePalette get palette => widget.palette;

  void _insert(String char) {
    widget.onKeyTap?.call(char);
    setState(() {
      _lastInserted = char;
    });
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
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(22),
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
                          if (widget.onKeyTap != null) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: palette.codeBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Interactive (Tap to insert)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: palette.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Shift Mode Toggle
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _shiftMode
                                ? palette.accent.withValues(alpha: 0.18)
                                : Colors.transparent,
                            side: BorderSide(
                              color: _shiftMode ? palette.accent : palette.border,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: Icon(
                            Icons.arrow_upward,
                            size: 13,
                            color: _shiftMode ? palette.accent : palette.muted,
                          ),
                          label: Text(
                            'Shift ⇧',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _shiftMode ? palette.accent : palette.fg,
                            ),
                          ),
                          onPressed: () =>
                              setState(() => _shiftMode = !_shiftMode),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: palette.muted),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

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
                        const SizedBox(height: 5),
                        _buildRow(_row2),
                        const SizedBox(height: 5),
                        _buildRow(_row3),
                        const SizedBox(height: 5),
                        _buildRow(_row4),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Vatthulu & Conjuncts Bar (వత్తులు & సంయుక్తాక్షరాలు)
                _buildVatthuluBar(),
                const SizedBox(height: 12),

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Typing Rules & Guninthalu (Matras):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: palette.fg,
                            ),
                          ),
                          if (_lastInserted != null)
                            Text(
                              'Inserted: $_lastInserted',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: palette.accent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          _tipItem('Vowels / Matras:',
                              'e=ా, r=ి, w=ీ, i=ు, p=ూ, u=ె, o=ే, [=ై, t=ొ, y=ో, ]=ౌ, W=ృ, E=ౄ'),
                          _tipItem('Halant / Otthu:',
                              'h key (e.g. j + h + j = క్క; hh = ZWNJ వాక్)'),
                          _tipItem('Anusvara / Visarga:',
                              'g = ం (అనుస్వార), G = ః (విసర్గ)'),
                          _tipItem('Special Ligatures:',
                              'Y=క్ష, N=క్ష్య, U=శ్రీ, Q=క్ష్మి, {=క్ష్మ, O=ష్ట, P=ష్ట్ర'),
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

  Widget _buildVatthuluBar() {
    final chips = <_VatthuChip>[
      _VatthuChip('్ (Pollu)', '\u0C4D'),
      _VatthuChip('ZWNJ', IndicEngine.zwnj),
      _VatthuChip('ZWJ', IndicEngine.zwj),
      _VatthuChip('ం (Sunna)', '\u0C02'),
      _VatthuChip('ః (Visarga)', '\u0C03'),
      _VatthuChip('క్ష', '\u0C15\u0C4D\u0C37'),
      _VatthuChip('క్ష్య', '\u0C15\u0C4D\u0C37\u0C4D\u0C2F'),
      _VatthuChip('శ్రీ', '\u0C36\u0C4D\u0C30\u0C40'),
      _VatthuChip('క్ష్మి', '\u0C15\u0C4D\u0C37\u0C4D\u0C2E\u0C3F'),
      _VatthuChip('క్ష్మ', '\u0C15\u0C4D\u0C37\u0C4D\u0C2E'),
      _VatthuChip('ష్ట', '\u0C37\u0C4D\u0C1F'),
      _VatthuChip('ష్ట్ర', '\u0C37\u0C4D\u0C1F\u0C4D\u0C30'),
      _VatthuChip('్క (క-వత్తు)', '\u0C4D\u0C15'),
      _VatthuChip('్గ (గ-వత్తు)', '\u0C4D\u0C17'),
      _VatthuChip('్చ (చ-వత్తు)', '\u0C4D\u0C1A'),
      _VatthuChip('్జ (జ-వత్తు)', '\u0C4D\u0C1C'),
      _VatthuChip('్ట (ట-వత్తు)', '\u0C4D\u0C1F'),
      _VatthuChip('్త (త-వత్తు)', '\u0C4D\u0C24'),
      _VatthuChip('్ద (ద-వత్తు)', '\u0C4D\u0C26'),
      _VatthuChip('్న (న-వత్తు)', '\u0C4D\u0C28'),
      _VatthuChip('్ప (ప-వత్తు)', '\u0C4D\u0C2A'),
      _VatthuChip('్బ (బ-వత్తు)', '\u0C4D\u0C2C'),
      _VatthuChip('్మ (మ-వత్తు)', '\u0C4D\u0C2E'),
      _VatthuChip('్య (య-వత్తు)', '\u0C4D\u0C2F'),
      _VatthuChip('్ర (ర-వత్తు)', '\u0C4D\u0C30'),
      _VatthuChip('్ల (ల-వత్తు)', '\u0C4D\u0C32'),
      _VatthuChip('్వ (వ-వత్తు)', '\u0C4D\u0C35'),
      _VatthuChip('్స (స-వత్తు)', '\u0C4D\u0C38'),
      _VatthuChip('్ళ (ళ-వత్తు)', '\u0C4D\u0C33'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.toolbarBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'వత్తులు & సంయుక్తాక్షరాలు (Quick Vatthulu & Conjuncts):',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Tap to insert',
                style: TextStyle(
                  fontSize: 10,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final chip in chips) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => _insert(chip.value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: palette.bg,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: palette.fg,
                          fontFamilyFallback: const [
                            'Noto Sans Telugu',
                            'Gautami'
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ],
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
    final activeShift = _shiftMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _insert(activeShift ? k.shift : k.normal),
        hoverColor: palette.accent.withValues(alpha: 0.1),
        child: Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: activeShift
                ? palette.toolbarBg.withValues(alpha: 0.95)
                : palette.toolbarBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: activeShift
                  ? palette.accent.withValues(alpha: 0.35)
                  : palette.border,
            ),
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
              // Top row: Latin Shift on left, Shift Telugu/symbol on right
              InkWell(
                onTap: () => _insert(k.shift),
                borderRadius: BorderRadius.circular(3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      k.upperLatin,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: activeShift ? palette.accent : palette.muted,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        k.shift,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: activeShift ? 11.5 : 10,
                          fontWeight:
                              activeShift ? FontWeight.w800 : FontWeight.bold,
                          color: activeShift ? palette.accent : palette.accent.withValues(alpha: 0.85),
                          fontFamilyFallback: const [
                            'Noto Sans Telugu',
                            'Gautami'
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom row: Latin Normal on left, Normal Telugu/symbol on right
              InkWell(
                onTap: () => _insert(k.normal),
                borderRadius: BorderRadius.circular(3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      k.lowerLatin,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: palette.muted.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      k.normal,
                      style: TextStyle(
                        fontSize: activeShift ? 11.5 : 13,
                        fontWeight:
                            activeShift ? FontWeight.w500 : FontWeight.w600,
                        color: activeShift ? palette.muted : palette.fg,
                        fontFamilyFallback: const [
                          'Noto Sans Telugu',
                          'Gautami'
                        ],
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<_KeyInfo> _row1 = [
    _KeyInfo('1', '1', '!', '!'),
    _KeyInfo('2', '2', "'", "'"),
    _KeyInfo('3', '3', '%', '%'),
    _KeyInfo('4', '4', 'ై', 'ౖ'),
    _KeyInfo('5', '5', '(', '('),
    _KeyInfo('6', '6', '-', '-'),
    _KeyInfo('7', '7', '|', '|'),
    _KeyInfo('8', '8', "'", "'"),
    _KeyInfo('9', '9', '(', '('),
    _KeyInfo('0', '0', ')', ')'),
    _KeyInfo('×', '×', '÷', '÷'),
    _KeyInfo('=', '=', '+', '+'),
  ];

  static const List<_KeyInfo> _row2 = [
    _KeyInfo('Q', 'అ', 'క్ష్మి'),
    _KeyInfo('W', 'ఈ', 'ఋ'),
    _KeyInfo('E', 'ఆ', 'ౠ'),
    _KeyInfo('R', 'ఇ', 'ఙ'),
    _KeyInfo('T', 'ఒ', 'ఞ'),
    _KeyInfo('Y', 'ఓ', 'క్ష'),
    _KeyInfo('U', 'ఎ', 'శ్రీ'),
    _KeyInfo('I', 'ఉ', '/'),
    _KeyInfo('O', 'ఏ', 'ష్ట'),
    _KeyInfo('P', 'ఊ', 'ష్ట్ర'),
    _KeyInfo('[', 'ఐ', 'క్ష్మ', '{'),
    _KeyInfo(']', 'ఔ', '!', '}'),
    _KeyInfo(r'\', ':', ':', '|'),
  ];

  static const List<_KeyInfo> _row3 = [
    _KeyInfo('A', 'ల', 'ళ'),
    _KeyInfo('S', 'త', 'థ'),
    _KeyInfo('D', 'ద', 'ధ'),
    _KeyInfo('F', 'వ', 'శ'),
    _KeyInfo('G', 'ం', ':'),
    _KeyInfo('H', '్', '్'),
    _KeyInfo('J', 'క', 'ఖ'),
    _KeyInfo('K', 'ర', 'ఱ'),
    _KeyInfo('L', 'న', 'ణ'),
    _KeyInfo(';', 'ప', 'ఫ', ':'),
    _KeyInfo("'", 'స', 'ష', '"'),
  ];

  static const List<_KeyInfo> _row4 = [
    _KeyInfo('Z', 'ట', 'ఠ'),
    _KeyInfo('X', 'గ', 'ఘ'),
    _KeyInfo('C', 'డ', 'ఢ'),
    _KeyInfo('V', 'బ', 'భ'),
    _KeyInfo('B', 'మ', 'హ'),
    _KeyInfo('N', 'య', 'క్ష్య'),
    _KeyInfo('M', 'చ', 'ఛ'),
    _KeyInfo(',', ',', ';', '<'),
    _KeyInfo('.', '.', '?', '>'),
    _KeyInfo('/', 'జ', 'ఝ', '?'),
  ];
}

class _KeyInfo {
  final String latin;
  final String normal;
  final String shift;
  final String? latinShift;

  const _KeyInfo(this.latin, this.normal, this.shift, [this.latinShift]);

  String get upperLatin => latinShift ?? latin.toUpperCase();
  String get lowerLatin => latinShift != null ? latin : latin.toLowerCase();
}

class _VatthuChip {
  final String label;
  final String value;
  const _VatthuChip(this.label, this.value);
}
