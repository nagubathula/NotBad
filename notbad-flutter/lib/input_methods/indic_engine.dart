/// Indic script input engine for Telugu and other Indian languages.
/// Supports both phonetic (English transliteration) and InScript keyboard layouts.
library;

enum InputLanguage {
  english('english', 'English', 'EN'),
  teluguAnu('telugu_anu', 'Telugu (Anu Script / Apple)', 'తె(అను)'),
  teluguPhonetic('telugu_phonetic', 'Telugu (Phonetic)', 'తె'),
  teluguInscript('telugu_inscript', 'Telugu (InScript)', 'తె⌨'),
  hindiPhonetic('hindi_phonetic', 'Hindi (Phonetic)', 'हि');

  final String id;
  final String label;
  final String badge;

  const InputLanguage(this.id, this.label, this.badge);

  static InputLanguage fromId(String? id) {
    return InputLanguage.values.firstWhere(
      (lang) => lang.id == id,
      orElse: () => InputLanguage.english,
    );
  }
}

class IndicEngine {
  /// Converts an English phonetic string to Telugu Unicode script.
  static String transliterateTelugu(String input) {
    if (input.isEmpty) return '';

    final sb = StringBuffer();
    var i = 0;
    final len = input.length;

    while (i < len) {
      // 1. Try matching multi-letter consonants first
      final matchedConsonant = _matchConsonant(input, i, _teluguConsonants);
      if (matchedConsonant != null) {
        final cCode = matchedConsonant.teluguBase;
        i += matchedConsonant.length;

        // Check if immediately followed by a vowel
        if (i < len) {
          final matchedMatra = _matchMatra(input, i, _teluguMatras);
          if (matchedMatra != null) {
            // Consonant + Matra
            sb.write(cCode);
            if (matchedMatra.matra.isNotEmpty) {
              sb.write(matchedMatra.matra);
            }
            i += matchedMatra.length;
            continue;
          }
        }

        // Consonant followed by another consonant or end-of-string:
        // By default, add halant (virama '్')
        sb.write(cCode);
        sb.write('\u0C4D'); // Telugu Virama (halant / pollu)
        continue;
      }

      // 2. Try matching independent vowels
      final matchedVowel = _matchVowel(input, i, _teluguVowels);
      if (matchedVowel != null) {
        sb.write(matchedVowel.vowel);
        i += matchedVowel.length;
        continue;
      }

      // 3. Special modifiers (anusvara 'M' / 'am' / visarga 'H')
      if (input[i] == 'M') {
        sb.write('\u0C02'); // Anusvara
        i++;
        continue;
      }
      if (input[i] == 'H') {
        sb.write('\u0C03'); // Visarga
        i++;
        continue;
      }

      // 4. Pass-through (digits, punctuation, or unmapped characters)
      sb.write(input[i]);
      i++;
    }

    return sb.toString();
  }

  /// Converts an English phonetic string to Hindi (Devanagari) Unicode script.
  static String transliterateHindi(String input) {
    if (input.isEmpty) return '';

    final sb = StringBuffer();
    var i = 0;
    final len = input.length;

    while (i < len) {
      final matchedConsonant = _matchConsonant(input, i, _hindiConsonants);
      if (matchedConsonant != null) {
        final cCode = matchedConsonant.teluguBase;
        i += matchedConsonant.length;

        if (i < len) {
          final matchedMatra = _matchMatra(input, i, _hindiMatras);
          if (matchedMatra != null) {
            sb.write(cCode);
            if (matchedMatra.matra.isNotEmpty) {
              sb.write(matchedMatra.matra);
            }
            i += matchedMatra.length;
            continue;
          }
        }

        sb.write(cCode);
        sb.write('\u094D'); // Devanagari Virama
        continue;
      }

      final matchedVowel = _matchVowel(input, i, _hindiVowels);
      if (matchedVowel != null) {
        sb.write(matchedVowel.vowel);
        i += matchedVowel.length;
        continue;
      }

      if (input[i] == 'M') {
        sb.write('\u0902'); // Anusvara
        i++;
        continue;
      }
      if (input[i] == 'H') {
        sb.write('\u0903'); // Visarga
        i++;
        continue;
      }

      sb.write(input[i]);
      i++;
    }

    return sb.toString();
  }

  /// Maps a single key character in Telugu InScript layout.
  static String? mapTeluguInscript(String char) {
    return _teluguInscriptMap[char];
  }

  /// Checks if a character code is a Telugu consonant or virama.
  static bool isTeluguConsonant(int codeUnit) {
    return (codeUnit >= 0x0C15 && codeUnit <= 0x0C39) ||
        (codeUnit >= 0x0C58 && codeUnit <= 0x0C5A) ||
        codeUnit == 0x0C4D;
  }

  /// Maps a key in the widely used Anu Script / Apple Telugu keyboard layout.
  /// [hasPrecedingConsonant] attaches vowel matras (guninthalu) to consonants.
  static String? mapTeluguAnu(String char,
      {bool hasPrecedingConsonant = false}) {
    if (char == 'h') return '\u0C4D'; // Virama/pollu '్'
    if (char == 'g') return '\u0C02'; // Anusvara 'ం'
    if (char == 'G') return '\u0C03'; // Visarga 'ః'

    // If preceded by a consonant, attach vowel matra (gunintham)
    if (hasPrecedingConsonant && _teluguAnuMatras.containsKey(char)) {
      return _teluguAnuMatras[char];
    }
    // Independent vowels (at word start or after space/punctuation)
    if (!hasPrecedingConsonant &&
        _teluguAnuIndependentVowels.containsKey(char)) {
      return _teluguAnuIndependentVowels[char];
    }
    // Consonants and special ligatures
    if (_teluguAnuConsonants.containsKey(char)) {
      return _teluguAnuConsonants[char];
    }
    // Fallback to independent vowel if typed anyway
    if (_teluguAnuIndependentVowels.containsKey(char)) {
      return _teluguAnuIndependentVowels[char];
    }
    return null;
  }

  static bool _isVowelChar(String ch) {
    return 'aeiouAEIOU'.contains(ch);
  }

  static _MatchResult? _matchConsonant(
      String input, int offset, List<_ConsonantMapping> table) {
    for (final entry in table) {
      if (input.startsWith(entry.roman, offset)) {
        return _MatchResult(entry.roman.length, entry.scriptChar);
      }
    }
    return null;
  }

  static _MatraResult? _matchMatra(
      String input, int offset, List<_MatraMapping> table) {
    for (final entry in table) {
      if (input.startsWith(entry.roman, offset)) {
        if (entry.roman == 'am') {
          final nextIdx = offset + 2;
          if (nextIdx < input.length) {
            final nextChar = input[nextIdx];
            if (_isVowelChar(nextChar) || nextChar == 'm') {
              continue;
            }
          }
        }
        return _MatraResult(entry.roman.length, entry.matra);
      }
    }
    return null;
  }

  static _VowelResult? _matchVowel(
      String input, int offset, List<_VowelMapping> table) {
    for (final entry in table) {
      if (input.startsWith(entry.roman, offset)) {
        if (entry.roman == 'am') {
          final nextIdx = offset + 2;
          if (nextIdx < input.length) {
            final nextChar = input[nextIdx];
            if (_isVowelChar(nextChar) || nextChar == 'm') {
              continue;
            }
          }
        }
        return _VowelResult(entry.roman.length, entry.vowel);
      }
    }
    return null;
  }

  // --- Telugu Mapping Tables ---
  static const List<_ConsonantMapping> _teluguConsonants = [
    // 3-letter combos
    _ConsonantMapping('ksh', '\u0C15\u0C4D\u0C37'), // క్ష (క్+ష)
    _ConsonantMapping('Ksh', '\u0C15\u0C4D\u0C37'),
    _ConsonantMapping('jny', '\u0C1C\u0C4D\u0C1E'), // జ్ఞ
    _ConsonantMapping('dny', '\u0C1C\u0C4D\u0C1E'),
    _ConsonantMapping('shh', '\u0C37'), // ష
    _ConsonantMapping('chh', '\u0C1B'), // ఛ
    _ConsonantMapping('thh', '\u0C25'), // థ
    _ConsonantMapping('dhh', '\u0C27'), // ధ

    // 2-letter combos
    _ConsonantMapping('kh', '\u0C16'), // ఖ
    _ConsonantMapping('Kh', '\u0C16'),
    _ConsonantMapping('gh', '\u0C18'), // ఘ
    _ConsonantMapping('Gh', '\u0C18'),
    _ConsonantMapping('ch', '\u0C1A'), // చ
    _ConsonantMapping('Ch', '\u0C1B'), // ఛ
    _ConsonantMapping('jh', '\u0C1D'), // ఝ
    _ConsonantMapping('Jh', '\u0C1D'),
    _ConsonantMapping('Th', '\u0C20'), // ఠ
    _ConsonantMapping('Dh', '\u0C22'), // ఢ
    _ConsonantMapping('th', '\u0C25'), // థ
    _ConsonantMapping('dh', '\u0C27'), // ధ
    _ConsonantMapping('ph', '\u0C2B'), // ఫ
    _ConsonantMapping('Ph', '\u0C2B'),
    _ConsonantMapping('bh', '\u0C2D'), // భ
    _ConsonantMapping('Bh', '\u0C2D'),
    _ConsonantMapping('sh', '\u0C36'), // శ
    _ConsonantMapping('Sh', '\u0C37'), // ష
    _ConsonantMapping('rr', '\u0C31'), // ఱ

    // 1-letter combos
    _ConsonantMapping('k', '\u0C15'), // క
    _ConsonantMapping('K', '\u0C16'), // ఖ
    _ConsonantMapping('g', '\u0C17'), // గ
    _ConsonantMapping('G', '\u0C18'), // ఘ
    _ConsonantMapping('c', '\u0C1A'), // చ
    _ConsonantMapping('j', '\u0C1C'), // జ
    _ConsonantMapping('J', '\u0C1D'), // ఝ
    _ConsonantMapping('T', '\u0C1F'), // ట
    _ConsonantMapping('D', '\u0C21'), // డ
    _ConsonantMapping('N', '\u0C23'), // ణ
    _ConsonantMapping('t', '\u0C24'), // త
    _ConsonantMapping('d', '\u0C26'), // ద
    _ConsonantMapping('n', '\u0C28'), // న
    _ConsonantMapping('p', '\u0C2A'), // ప
    _ConsonantMapping('P', '\u0C2A'),
    _ConsonantMapping('f', '\u0C2B'), // ఫ
    _ConsonantMapping('F', '\u0C2B'),
    _ConsonantMapping('b', '\u0C2C'), // బ
    _ConsonantMapping('B', '\u0C2D'), // భ
    _ConsonantMapping('m', '\u0C2E'), // మ
    _ConsonantMapping('y', '\u0C2F'), // య
    _ConsonantMapping('r', '\u0C30'), // ర
    _ConsonantMapping('l', '\u0C32'), // ల
    _ConsonantMapping('L', '\u0C33'), // ళ
    _ConsonantMapping('v', '\u0C35'), // వ
    _ConsonantMapping('w', '\u0C35'), // వ
    _ConsonantMapping('S', '\u0C36'), // శ
    _ConsonantMapping('s', '\u0C38'), // స
    _ConsonantMapping('h', '\u0C39'), // హ
    _ConsonantMapping('R', '\u0C31'), // ఱ
  ];

  static const List<_MatraMapping> _teluguMatras = [
    _MatraMapping('aha', '\u0C03'), // ః
    _MatraMapping('am', '\u0C02'), // ం
    _MatraMapping('aa', '\u0C3E'), // ా
    _MatraMapping('ee', '\u0C40'), // ీ
    _MatraMapping('ii', '\u0C40'), // ీ
    _MatraMapping('oo', '\u0C42'), // ూ
    _MatraMapping('uu', '\u0C42'), // ూ
    _MatraMapping('ai', '\u0C48'), // ై
    _MatraMapping('au', '\u0C4C'), // ౌ
    _MatraMapping('ou', '\u0C4C'), // ౌ
    _MatraMapping('ea', '\u0C47'), // ే
    _MatraMapping('oa', '\u0C4B'), // ో
    _MatraMapping('Ru', '\u0C43'), // ృ
    _MatraMapping('a', ''), // inherent 'a' (no matra, removes virama)
    _MatraMapping('A', '\u0C3E'), // ా
    _MatraMapping('i', '\u0C3F'), // ి
    _MatraMapping('I', '\u0C40'), // ీ
    _MatraMapping('u', '\u0C41'), // ు
    _MatraMapping('U', '\u0C42'), // ూ
    _MatraMapping('e', '\u0C46'), // ె
    _MatraMapping('E', '\u0C47'), // ే
    _MatraMapping('o', '\u0C4A'), // ొ
    _MatraMapping('O', '\u0C4B'), // ో
    _MatraMapping('M', '\u0C02'), // ం
    _MatraMapping('H', '\u0C03'), // ః
  ];

  static const List<_VowelMapping> _teluguVowels = [
    _VowelMapping('aha', '\u0C05\u0C03'), // అః
    _VowelMapping('am', '\u0C05\u0C02'), // అం
    _VowelMapping('aa', '\u0C06'), // ఆ
    _VowelMapping('ee', '\u0C08'), // ఈ
    _VowelMapping('ii', '\u0C08'), // ఈ
    _VowelMapping('oo', '\u0C0A'), // ఊ
    _VowelMapping('uu', '\u0C0A'), // ఊ
    _VowelMapping('Ru', '\u0C0B'), // ఋ
    _VowelMapping('ai', '\u0C10'), // ఐ
    _VowelMapping('au', '\u0C14'), // ఔ
    _VowelMapping('ou', '\u0C14'), // ఔ
    _VowelMapping('ea', '\u0C0F'), // ఏ
    _VowelMapping('oa', '\u0C13'), // ఓ
    _VowelMapping('a', '\u0C05'), // అ
    _VowelMapping('A', '\u0C06'), // ఆ
    _VowelMapping('i', '\u0C07'), // ఇ
    _VowelMapping('I', '\u0C08'), // ఈ
    _VowelMapping('u', '\u0C09'), // ఉ
    _VowelMapping('U', '\u0C0A'), // ఊ
    _VowelMapping('e', '\u0C0E'), // ఎ
    _VowelMapping('E', '\u0C0F'), // ఏ
    _VowelMapping('o', '\u0C12'), // ఒ
    _VowelMapping('O', '\u0C13'), // ఓ
  ];

  // --- Telugu InScript Map ---
  static const Map<String, String> _teluguInscriptMap = {
    'q': '\u0C4C', // ౌ
    'Q': '\u0C14', // ఔ
    'w': '\u0C48', // ై
    'W': '\u0C10', // ఐ
    'e': '\u0C3E', // ా
    'E': '\u0C06', // ఆ
    'r': '\u0C40', // ీ
    'R': '\u0C08', // ఈ
    't': '\u0C42', // ూ
    'T': '\u0C0A', // ఊ
    'y': '\u0C2C', // బ
    'Y': '\u0C2D', // భ
    'u': '\u0C39', // హ
    'U': '\u0C19', // ఙ
    'i': '\u0C17', // గ
    'I': '\u0C18', // ఘ
    'o': '\u0C26', // ద
    'O': '\u0C27', // ధ
    'p': '\u0C1C', // జ
    'P': '\u0C1D', // ఝ
    '[': '\u0C21', // డ
    '{': '\u0C22', // ఢ
    ']': '\u0C4A', // ొ
    '}': '\u0C13', // ఓ
    'a': '\u0C4B', // ో
    'A': '\u0C12', // ఒ
    's': '\u0C47', // ే
    'S': '\u0C0F', // ఏ
    'd': '\u0C4D', // ్ (virama)
    'D': '\u0C05', // అ
    'f': '\u0C3F', // ి
    'F': '\u0C07', // ఇ
    'g': '\u0C41', // ు
    'G': '\u0C09', // ఉ
    'h': '\u0C2A', // ప
    'H': '\u0C2B', // ఫ
    'j': '\u0C30', // ర
    'J': '\u0C31', // ఱ
    'k': '\u0C15', // క
    'K': '\u0C16', // ఖ
    'l': '\u0C24', // త
    'L': '\u0C25', // థ
    ';': '\u0C1A', // చ
    ':': '\u0C1B', // ఛ
    "'": '\u0C1F', // ట
    '"': '\u0C20', // ఠ
    'z': '\u0C46', // ె
    'Z': '\u0C0E', // ఎ
    'x': '\u0C02', // ం
    'X': '\u0C01', // ఁ
    'c': '\u0C2E', // మ
    'C': '\u0C23', // ణ
    'v': '\u0C28', // న
    'b': '\u0C35', // వ
    'n': '\u0C32', // ల
    'N': '\u0C33', // ళ
    'm': '\u0C38', // స
    'M': '\u0C36', // శ
    '<': '\u0C37', // ష
    '>': '\u0964', // ।
    '/': '\u0C2F', // య
  };

  // --- Hindi (Devanagari) Tables ---
  static const List<_ConsonantMapping> _hindiConsonants = [
    _ConsonantMapping('ksh', '\u0915\u094D\u0937'),
    _ConsonantMapping('Ksh', '\u0915\u094D\u0937'),
    _ConsonantMapping('jny', '\u091C\u094D\u091E'),
    _ConsonantMapping('gy', '\u091C\u094D\u091E'),
    _ConsonantMapping('shh', '\u0937'),
    _ConsonantMapping('chh', '\u091B'),
    _ConsonantMapping('thh', '\u0925'),
    _ConsonantMapping('dhh', '\u0927'),
    _ConsonantMapping('kh', '\u0916'),
    _ConsonantMapping('Kh', '\u0916'),
    _ConsonantMapping('gh', '\u0918'),
    _ConsonantMapping('Gh', '\u0918'),
    _ConsonantMapping('ch', '\u091A'),
    _ConsonantMapping('Ch', '\u091B'),
    _ConsonantMapping('jh', '\u091D'),
    _ConsonantMapping('Jh', '\u091D'),
    _ConsonantMapping('Th', '\u0920'),
    _ConsonantMapping('Dh', '\u0922'),
    _ConsonantMapping('th', '\u0925'),
    _ConsonantMapping('dh', '\u0927'),
    _ConsonantMapping('ph', '\u092B'),
    _ConsonantMapping('bh', '\u092D'),
    _ConsonantMapping('Bh', '\u092D'),
    _ConsonantMapping('sh', '\u0936'),
    _ConsonantMapping('Sh', '\u0937'),
    _ConsonantMapping('k', '\u0915'),
    _ConsonantMapping('K', '\u0916'),
    _ConsonantMapping('g', '\u0917'),
    _ConsonantMapping('G', '\u0918'),
    _ConsonantMapping('c', '\u091A'),
    _ConsonantMapping('j', '\u091C'),
    _ConsonantMapping('J', '\u091D'),
    _ConsonantMapping('T', '\u091F'),
    _ConsonantMapping('D', '\u0921'),
    _ConsonantMapping('N', '\u0923'),
    _ConsonantMapping('t', '\u0924'),
    _ConsonantMapping('d', '\u0926'),
    _ConsonantMapping('n', '\u0928'),
    _ConsonantMapping('p', '\u092A'),
    _ConsonantMapping('P', '\u092A'),
    _ConsonantMapping('f', '\u092B'),
    _ConsonantMapping('F', '\u092B'),
    _ConsonantMapping('b', '\u092C'),
    _ConsonantMapping('B', '\u092D'),
    _ConsonantMapping('m', '\u092E'),
    _ConsonantMapping('y', '\u092F'),
    _ConsonantMapping('r', '\u0930'),
    _ConsonantMapping('l', '\u0932'),
    _ConsonantMapping('v', '\u0935'),
    _ConsonantMapping('w', '\u0935'),
    _ConsonantMapping('S', '\u0936'),
    _ConsonantMapping('s', '\u0938'),
    _ConsonantMapping('h', '\u0939'),
  ];

  static const List<_MatraMapping> _hindiMatras = [
    _MatraMapping('aha', '\u0903'),
    _MatraMapping('am', '\u0902'),
    _MatraMapping('aa', '\u093E'),
    _MatraMapping('ee', '\u0940'),
    _MatraMapping('ii', '\u0940'),
    _MatraMapping('oo', '\u0942'),
    _MatraMapping('uu', '\u0942'),
    _MatraMapping('ai', '\u0948'),
    _MatraMapping('au', '\u094C'),
    _MatraMapping('ou', '\u094C'),
    _MatraMapping('Ru', '\u0943'),
    _MatraMapping('a', ''),
    _MatraMapping('A', '\u093E'),
    _MatraMapping('i', '\u093F'),
    _MatraMapping('I', '\u0940'),
    _MatraMapping('u', '\u0941'),
    _MatraMapping('U', '\u0942'),
    _MatraMapping('e', '\u0947'),
    _MatraMapping('E', '\u0947'),
    _MatraMapping('o', '\u094B'),
    _MatraMapping('O', '\u094B'),
    _MatraMapping('M', '\u0902'),
    _MatraMapping('H', '\u0903'),
  ];

  static const List<_VowelMapping> _hindiVowels = [
    _VowelMapping('aha', '\u0905\u0903'),
    _VowelMapping('am', '\u0905\u0902'),
    _VowelMapping('aa', '\u0906'),
    _VowelMapping('ee', '\u0908'),
    _VowelMapping('ii', '\u0908'),
    _VowelMapping('oo', '\u090A'),
    _VowelMapping('uu', '\u090A'),
    _VowelMapping('Ru', '\u090B'),
    _VowelMapping('ai', '\u0910'),
    _VowelMapping('au', '\u0914'),
    _VowelMapping('ou', '\u0914'),
    _VowelMapping('a', '\u0905'),
    _VowelMapping('A', '\u0906'),
    _VowelMapping('i', '\u0907'),
    _VowelMapping('I', '\u0908'),
    _VowelMapping('u', '\u0909'),
    _VowelMapping('U', '\u090A'),
    _VowelMapping('e', '\u090F'),
    _VowelMapping('E', '\u090F'),
    _VowelMapping('o', '\u0913'),
    _VowelMapping('O', '\u0913'),
  ];

  // --- Anu Script / Apple Layout Mapping Tables ---
  static const Map<String, String> _teluguAnuConsonants = {
    // Row 3 (A-row)
    'a': '\u0C32', // ల
    'A': '\u0C33', // ళ
    's': '\u0C24', // త
    'S': '\u0C25', // థ
    'd': '\u0C26', // ద
    'D': '\u0C27', // ధ
    'f': '\u0C2A', // ప
    'F': '\u0C2B', // ఫ
    'j': '\u0C15', // క
    'J': '\u0C16', // ఖ
    'k': '\u0C30', // ర
    'l': '\u0C38', // స
    'L': '\u0C23', // ణ
    ';': '\u0C35', // వ
    ':': '\u0C36', // శ
    "'": '\u0C28', // న
    '"': '\u0C37', // ష

    // Row 4 (Z-row)
    'z': '\u0C1F', // ట
    'Z': '\u0C20', // ఠ
    'x': '\u0C17', // గ
    'X': '\u0C18', // ఘ
    'c': '\u0C21', // డ
    'C': '\u0C22', // ఢ
    'v': '\u0C2C', // బ
    'V': '\u0C2D', // భ
    'b': '\u0C2E', // మ
    'B': '\u0C39', // హ
    'n': '\u0C2F', // య
    'm': '\u0C1A', // చ
    'M': '\u0C1B', // ఛ
    '/': '\u0C1C', // జ
    '?': '\u0C1D', // ఝ

    // Upper row / ligatures
    'R': '\u0C19', // ఙ
    'T': '\u0C1E', // ఞ
    'Y': '\u0C15\u0C4D\u0C37', // క్ష (క+్+ష)
    'U': '\u0C36\u0C4D\u0C30\u0C40', // శ్రీ (శ+్+ర+ీ)
    'O': '\u0C30\u0C4D', // ర్
    'P': '\u0C15\u0C43', // కృ
    '[': '\u0C31', // ఱ
    '{': '\u0C15\u0C4D\u0C37\u0C4D\u0C2E', // క్ష serial
    'Q': '\u0C15\u0C4D\u0C37\u0C4D\u0C2E\u0C3F', // క్ష serial
  };

  static const Map<String, String> _teluguAnuIndependentVowels = {
    'q': '\u0C05', // అ
    'e': '\u0C06', // ఆ
    'r': '\u0C07', // ఇ
    'w': '\u0C08', // ఈ
    'i': '\u0C09', // ఉ
    'p': '\u0C0A', // ఊ
    'E': '\u0C0B', // ఋ
    'W': '\u0C60', // ౠ
    'u': '\u0C0E', // ఎ
    'o': '\u0C0F', // ఏ
    't': '\u0C12', // ఒ
    'y': '\u0C13', // ఓ
    ']': '\u0C14', // ఔ
  };

  static const Map<String, String> _teluguAnuMatras = {
    'e': '\u0C3E', // ా (ఆ matra)
    'r': '\u0C3F', // ి (ఇ matra)
    'w': '\u0C40', // ీ (ఈ matra)
    'i': '\u0C41', // ు (ఉ matra)
    'p': '\u0C42', // ూ (ఊ matra)
    'E': '\u0C43', // ృ (ఋ matra)
    'W': '\u0C44', // ౄ (ౠ matra)
    'u': '\u0C46', // ె (ఎ matra)
    'o': '\u0C47', // ే (ఏ matra)
    't': '\u0C4A', // ొ (ఒ matra)
    'y': '\u0C4B', // ో (ఓ matra)
    ']': '\u0C4C', // ౌ (ఔ matra)
  };
}

class _ConsonantMapping {
  final String roman;
  final String scriptChar;
  const _ConsonantMapping(this.roman, this.scriptChar);
}

class _MatraMapping {
  final String roman;
  final String matra;
  const _MatraMapping(this.roman, this.matra);
}

class _VowelMapping {
  final String roman;
  final String vowel;
  const _VowelMapping(this.roman, this.vowel);
}

class _MatchResult {
  final int length;
  final String teluguBase;
  const _MatchResult(this.length, this.teluguBase);
}

class _MatraResult {
  final int length;
  final String matra;
  const _MatraResult(this.length, this.matra);
}

class _VowelResult {
  final int length;
  final String vowel;
  const _VowelResult(this.length, this.vowel);
}
