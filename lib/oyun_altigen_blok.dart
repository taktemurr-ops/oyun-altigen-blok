/// Altıgen Blok: altıgen tahtaya parça yerleştir, üç yöndeki sıraları temizle.
/// Blok Oyunları merkez uygulamasının oyunu.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';

import 'src/hex_rules.dart';
import 'src/hex_view.dart';

export 'src/hex_engine.dart';
export 'src/hex_rules.dart';

final altigenBlokConfig = GameConfig(
  gameId: altigenBlokId,
  title: const ['Altıgen Blok', 'Hex Blocks', 'Hex-Blöcke', 'Bloques Hexagonales', 'Blocs Hexagonaux'],
  tagline: const [
    'Üç yönde sıra tamamla!',
    'Complete lines in three directions!',
    'Reihen in drei Richtungen füllen!',
    '¡Completa líneas en tres direcciones!',
    'Complétez des lignes dans trois directions !',
  ],
  seedColor: const Color(0xFFFFB300),
  icon: Icons.hexagon_rounded,
  rules: HexRules(),
  buildPlay: (ctx) => HexView(ctx: ctx),
  tutorial: const [
    TutorialStep(Icons.pan_tool_alt, [
      'Parçayı altıgen tahtaya sürükle ya da parçaya, sonra kareye dokun.',
      'Drag a piece onto the board, or tap the piece then a cell.',
      'Ziehe ein Teil aufs Brett oder tippe Teil und Feld an.',
      'Arrastra una pieza o toca la pieza y luego la casilla.',
      'Glissez une pièce ou touchez la pièce puis une case.',
    ]),
    TutorialStep(Icons.hexagon_outlined, [
      'Bir sıra üç yönden biriyle dolarsa silinir. Aynı anda birden çok sıra bonus verir.',
      'A full line in any of the three directions clears. Several at once give a bonus.',
      'Volle Reihen in jeder der drei Richtungen verschwinden.',
      'Una línea llena en cualquiera de las tres direcciones desaparece.',
      'Une ligne pleine dans l\'une des trois directions disparaît.',
    ]),
  ],
);
