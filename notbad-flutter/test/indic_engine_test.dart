import 'package:flutter_test/flutter_test.dart';
import 'package:notbad_flutter/input_methods/indic_engine.dart';

void main() {
  group('IndicEngine Transliteration', () {
    test('transliterates Telugu vowels', () {
      expect(IndicEngine.transliterateTelugu('a'), equals('అ'));
      expect(IndicEngine.transliterateTelugu('aa'), equals('ఆ'));
      expect(IndicEngine.transliterateTelugu('i'), equals('ఇ'));
      expect(IndicEngine.transliterateTelugu('ee'), equals('ఈ'));
      expect(IndicEngine.transliterateTelugu('u'), equals('ఉ'));
      expect(IndicEngine.transliterateTelugu('oo'), equals('ఊ'));
      expect(IndicEngine.transliterateTelugu('e'), equals('ఎ'));
      expect(IndicEngine.transliterateTelugu('E'), equals('ఏ'));
      expect(IndicEngine.transliterateTelugu('ai'), equals('ఐ'));
      expect(IndicEngine.transliterateTelugu('o'), equals('ఒ'));
      expect(IndicEngine.transliterateTelugu('O'), equals('ఓ'));
      expect(IndicEngine.transliterateTelugu('au'), equals('ఔ'));
    });

    test('transliterates common Telugu words', () {
      expect(IndicEngine.transliterateTelugu('amma'), equals('అమ్మ'));
      expect(IndicEngine.transliterateTelugu('telugu'), equals('తెలుగు'));
      expect(IndicEngine.transliterateTelugu('namaskaaram'), equals('నమస్కారం'));
      expect(IndicEngine.transliterateTelugu('pustakam'), equals('పుస్తకం'));
      expect(IndicEngine.transliterateTelugu('bhaarat'), equals('భారత్'));
    });

    test('transliterates Hindi words', () {
      expect(IndicEngine.transliterateHindi('namaste'), equals('नमस्ते'));
      expect(IndicEngine.transliterateHindi('bhaarata'), equals('भारत'));
    });
  });

  group('IndicEngine Keyboard Layouts', () {
    test('maps InScript characters', () {
      expect(IndicEngine.mapTeluguInscript('k'), equals('క'));
      expect(IndicEngine.mapTeluguInscript('d'), equals('్'));
      expect(IndicEngine.mapTeluguInscript('e'), equals('ా'));
    });

    test('maps Anu Script consonants, halant, and anusvara', () {
      expect(IndicEngine.mapTeluguAnu('j'), equals('క'));
      expect(IndicEngine.mapTeluguAnu('J'), equals('ఖ'));
      expect(IndicEngine.mapTeluguAnu('s'), equals('త'));
      expect(IndicEngine.mapTeluguAnu('a'), equals('ల'));
      expect(IndicEngine.mapTeluguAnu('b'), equals('మ'));
      expect(IndicEngine.mapTeluguAnu('h'), equals('్'));
      expect(IndicEngine.mapTeluguAnu('H'), equals('్'));
      expect(IndicEngine.mapTeluguAnu('g'), equals('ం'));
      expect(IndicEngine.mapTeluguAnu('G'), equals('ః'));
      expect(IndicEngine.mapTeluguAnu('f'), equals('వ'));
      expect(IndicEngine.mapTeluguAnu('F'), equals('శ'));
      expect(IndicEngine.mapTeluguAnu(';'), equals('ప'));
      expect(IndicEngine.mapTeluguAnu(':'), equals('ఫ'));
      expect(IndicEngine.mapTeluguAnu('l'), equals('న'));
      expect(IndicEngine.mapTeluguAnu('L'), equals('ణ'));
      expect(IndicEngine.mapTeluguAnu("'"), equals('స'));
      expect(IndicEngine.mapTeluguAnu('"'), equals('ష'));
      expect(IndicEngine.mapTeluguAnu('k'), equals('ర'));
      expect(IndicEngine.mapTeluguAnu('K'), equals('ఱ'));
      expect(IndicEngine.mapTeluguAnu('n'), equals('య'));
      expect(IndicEngine.mapTeluguAnu('N'), equals('క్ష్య'));
      expect(IndicEngine.mapTeluguAnu('O'), equals('ష్ట'));
      expect(IndicEngine.mapTeluguAnu('P'), equals('ష్ట్ర'));
      expect(IndicEngine.mapTeluguAnu('Y'), equals('క్ష'));
      expect(IndicEngine.mapTeluguAnu('U'), equals('శ్రీ'));
      expect(IndicEngine.mapTeluguAnu('Q'), equals('క్ష్మి'));
      expect(IndicEngine.mapTeluguAnu('['), equals('ఐ'));
      expect(IndicEngine.mapTeluguAnu('{'), equals('క్ష్మ'));
      expect(IndicEngine.mapTeluguAnu(']'), equals('ఔ'));
    });

    test('maps Anu Script vowels vs contextual matras', () {
      // Independent vowels
      expect(IndicEngine.mapTeluguAnu('e'), equals('ఆ'));
      expect(IndicEngine.mapTeluguAnu('W'), equals('ఋ'));
      expect(IndicEngine.mapTeluguAnu('E'), equals('ౠ'));

      // Contextual matras when preceded by a consonant
      expect(
          IndicEngine.mapTeluguAnu('e', hasPrecedingConsonant: true), equals('ా'));
      expect(
          IndicEngine.mapTeluguAnu('r', hasPrecedingConsonant: true), equals('ి'));
      expect(
          IndicEngine.mapTeluguAnu('w', hasPrecedingConsonant: true), equals('ీ'));
      expect(
          IndicEngine.mapTeluguAnu('i', hasPrecedingConsonant: true), equals('ు'));
      expect(
          IndicEngine.mapTeluguAnu('p', hasPrecedingConsonant: true), equals('ూ'));
      expect(
          IndicEngine.mapTeluguAnu('u', hasPrecedingConsonant: true), equals('ె'));
      expect(
          IndicEngine.mapTeluguAnu('o', hasPrecedingConsonant: true), equals('ే'));
      expect(
          IndicEngine.mapTeluguAnu('W', hasPrecedingConsonant: true), equals('ృ'));
      expect(
          IndicEngine.mapTeluguAnu('E', hasPrecedingConsonant: true), equals('ౄ'));
      expect(
          IndicEngine.mapTeluguAnu('[', hasPrecedingConsonant: true), equals('ై'));
      expect(
          IndicEngine.mapTeluguAnu(']', hasPrecedingConsonant: true), equals('ౌ'));
    });

    test('maps Anu Script number row symbols and math operators', () {
      expect(IndicEngine.mapTeluguAnu('-'), equals('×'));
      expect(IndicEngine.mapTeluguAnu('_'), equals('÷'));
      expect(IndicEngine.mapTeluguAnu(r'$'), equals('ౖ'));
      expect(IndicEngine.mapTeluguAnu('@'), equals("'"));
      expect(IndicEngine.mapTeluguAnu('#'), equals('%'));
      expect(IndicEngine.mapTeluguAnu('^'), equals('-'));
      expect(IndicEngine.mapTeluguAnu('&'), equals('|'));
      expect(IndicEngine.mapTeluguAnu('*'), equals("'"));
      expect(IndicEngine.mapTeluguAnu('}'), equals('!'));
    });

    test('validates matra detection and zero-width characters', () {
      expect(IndicEngine.isTeluguAnuMatraKey('e'), isTrue);
      expect(IndicEngine.isTeluguAnuMatraKey('r'), isTrue);
      expect(IndicEngine.isTeluguAnuMatraKey('['), isTrue);
      expect(IndicEngine.isTeluguAnuMatraKey(']'), isTrue);
      expect(IndicEngine.isTeluguAnuMatraKey('j'), isFalse);
      expect(IndicEngine.isTeluguAnuMatraKey('a'), isFalse);

      expect(IndicEngine.zwnj, equals('\u200C'));
      expect(IndicEngine.zwj, equals('\u200D'));
    });
  });
}
