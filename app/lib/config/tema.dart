// lib/config/tema.dart
//
// Tema central de SmartForm.
// Traduce los tokens de diseño del boceto HTML a Flutter (Material 3):
// paleta, tipografía (Sora + Manrope) y estilos reutilizables de componentes.
//
// Regla: las pantallas NUNCA definen colores "a mano"; siempre usan
// `Colores`, `Tipografia` y los helpers de este archivo. Así el diseño
// queda centralizado y cambiar un color/estilo se hace en un solo lugar.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta extraída del boceto. Los colores que venían en `oklch` ya están
/// convertidos a sRGB (hex). No instanciar: solo constantes estáticas.
class Colores {
  Colores._();

  // --- Neutros / superficies ---
  static const Color tinta = Color(0xFF1C1A17); // --ink  (texto principal)
  static const Color suave = Color(0xFF726C64); // --soft (texto secundario)
  static const Color linea = Color(0xFFECE7DF); // --line (bordes)
  static const Color fondoApp = Color(0xFFFAF8F5); // --app  (fondo claro)
  static const Color tarjeta = Color(0xFFFFFFFF); // --card
  static const Color oscuro = Color(0xFF141210); // --dark (tarjetas oscuras / entrenamiento)

  // --- Acento (naranja) --- oklch(0.7 0.2 45) -> #FE6A00
  static const Color acento = Color(0xFFFE6A00);
  static const Color acentoSuave = Color(0x1FFE6A00); // 12% (alpha 31)
  static const Color acentoTexto = Color(0xFF8A3A00); // texto sobre fondo acento-suave
  static const Color sobreAcento = Color(0xFF241000); // texto/íconos sobre acento sólido

  // --- OK (verde) --- oklch(0.6 0.13 155) -> #2C965D
  static const Color ok = Color(0xFF2C965D);
  static const Color okSuave = Color(0x242C965D); // 14% (alpha 36)
}

/// Radios, espaciados y medidas recurrentes del boceto.
class Medidas {
  Medidas._();

  static const double radioTarjeta = 20; // tarjetas grandes
  static const double radioInput = 14; // campos de texto
  static const double radioBoton = 16; // botones principales
  static const double radioChip = 20; // "pills" / etiquetas
  static const double alturaBoton = 56; // botón principal
  static const double alturaInput = 52; // campo de texto
  static const double paddingPantalla = 22; // margen lateral estándar
}

/// Tipografía: Sora para encabezados, Manrope para cuerpo.
/// Si en el futuro prefieres empaquetar las fuentes en assets (offline puro),
/// solo cambia aquí `GoogleFonts.sora(...)` por `TextStyle(fontFamily: 'Sora')`
/// y `GoogleFonts.manropeTextTheme` por un TextTheme con fontFamily: 'Manrope'.
class Tipografia {
  Tipografia._();

  /// Encabezado con Sora. `tracking` replica el `letter-spacing` del boceto
  /// (en CSS era -0.02em/-0.03em; aquí se escala con el tamaño).
  static TextStyle sora(
    double tam, {
    FontWeight peso = FontWeight.w800,
    Color color = Colores.tinta,
    double altura = 1.1,
    double tracking = -0.02,
  }) {
    return GoogleFonts.sora(
      fontSize: tam,
      fontWeight: peso,
      color: color,
      height: altura,
      letterSpacing: tracking * tam,
    );
  }

  /// Texto de cuerpo con Manrope.
  static TextStyle manrope(
    double tam, {
    FontWeight peso = FontWeight.w500,
    Color color = Colores.tinta,
    double altura = 1.4,
  }) {
    return GoogleFonts.manrope(
      fontSize: tam,
      fontWeight: peso,
      color: color,
      height: altura,
    );
  }

  /// Construye el TextTheme global: Manrope de base, encabezados en Sora.
  static TextTheme textTheme(TextTheme base) {
    final cuerpo = GoogleFonts.manropeTextTheme(base).apply(
      bodyColor: Colores.tinta,
      displayColor: Colores.tinta,
    );
    return cuerpo.copyWith(
      displayLarge: sora(33, peso: FontWeight.w800, altura: 1.05),
      displayMedium: sora(28, peso: FontWeight.w800),
      headlineLarge: sora(26, peso: FontWeight.w800),
      headlineMedium: sora(22, peso: FontWeight.w800),
      titleLarge: sora(19, peso: FontWeight.w800, altura: 1.2),
      titleMedium: sora(17, peso: FontWeight.w700, altura: 1.2),
      labelLarge: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Colores.sobreAcento,
      ),
    );
  }
}

/// Estilos reutilizables de componentes (botones, tarjetas, chips, inputs).
/// Se exponen como helpers en vez de solo CardTheme/ButtonTheme para ser
/// robustos entre versiones de Flutter y fáciles de usar desde cualquier
/// pantalla.
class Componentes {
  Componentes._();

  /// Decoración de tarjeta blanca con borde fino (el patrón del boceto).
  static BoxDecoration tarjeta({Color? fondo, double? radio}) => BoxDecoration(
        color: fondo ?? Colores.tarjeta,
        borderRadius: BorderRadius.circular(radio ?? Medidas.radioTarjeta),
        border: Border.all(color: Colores.linea),
      );

  /// Decoración de tarjeta oscura (racha, resumen, overlay).
  static BoxDecoration tarjetaOscura({double? radio}) => BoxDecoration(
        color: Colores.oscuro,
        borderRadius: BorderRadius.circular(radio ?? Medidas.radioTarjeta),
      );

  /// Estilo de botón principal (naranja, alto 56, texto oscuro).
  static ButtonStyle botonPrimario() => FilledButton.styleFrom(
        backgroundColor: Colores.acento,
        foregroundColor: Colores.sobreAcento,
        minimumSize: const Size.fromHeight(Medidas.alturaBoton),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medidas.radioBoton),
        ),
        textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800),
      );

  /// Estilo de botón secundario (contorno, fondo tarjeta).
  static ButtonStyle botonSecundario() => OutlinedButton.styleFrom(
        backgroundColor: Colores.tarjeta,
        foregroundColor: Colores.tinta,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: Colores.linea, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medidas.radioBoton),
        ),
        textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
      );

  /// "Pill" / etiqueta (chip) reutilizable.
  static Widget chip(
    String texto, {
    Color fondo = Colores.acentoSuave,
    Color color = Colores.acentoTexto,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(Medidas.radioChip),
      ),
      child: Text(
        texto,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Construye el ThemeData completo de la app. Se usa en `main.dart`.
ThemeData construirTema() {
  final base = ThemeData(brightness: Brightness.light, useMaterial3: true);

  final esquema = ColorScheme.fromSeed(
    seedColor: Colores.acento,
    brightness: Brightness.light,
  ).copyWith(
    primary: Colores.acento,
    onPrimary: Colores.sobreAcento,
    secondary: Colores.ok,
    surface: Colores.fondoApp,
    onSurface: Colores.tinta,
    outline: Colores.linea,
    surfaceTint: Colors.transparent, // evita el tintado M3 en tarjetas
  );

  return base.copyWith(
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondoApp,
    textTheme: Tipografia.textTheme(base.textTheme),
    filledButtonTheme: FilledButtonThemeData(style: Componentes.botonPrimario()),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: Componentes.botonSecundario()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colores.tarjeta,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: GoogleFonts.manrope(color: const Color(0xFFB6B0A7)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radioInput),
        borderSide: const BorderSide(color: Colores.linea),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radioInput),
        borderSide: const BorderSide(color: Colores.linea),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radioInput),
        borderSide: const BorderSide(color: Colores.acento, width: 1.6),
      ),
    ),
  );
}