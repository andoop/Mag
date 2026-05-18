import 'dart:convert';
import 'dart:typed_data';

import 'package:qr/qr.dart';

const String kQrCodeMimeType = 'image/svg+xml';

class QrCodeOptions {
  const QrCodeOptions({
    required this.text,
    this.size = 256,
    this.margin = 4,
    this.foregroundColor = '#111827',
    this.backgroundColor = '#FFFFFF',
    this.errorCorrectionLevel = 'M',
  });

  final String text;
  final int size;
  final int margin;
  final String foregroundColor;
  final String backgroundColor;
  final String errorCorrectionLevel;

  factory QrCodeOptions.fromJson(Map<String, dynamic> json) {
    return QrCodeOptions(
      text: json['text'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 256,
      margin: (json['margin'] as num?)?.toInt() ?? 4,
      foregroundColor: json['foregroundColor'] as String? ?? '#111827',
      backgroundColor: json['backgroundColor'] as String? ?? '#FFFFFF',
      errorCorrectionLevel: json['errorCorrectionLevel'] as String? ?? 'M',
    );
  }
}

class QrCodeArtifact {
  const QrCodeArtifact({
    required this.svg,
    required this.dataUrl,
    required this.mimeType,
    required this.size,
    required this.moduleCount,
    required this.textBytes,
  });

  final String svg;
  final String dataUrl;
  final String mimeType;
  final int size;
  final int moduleCount;
  final int textBytes;

  Uint8List get bytes => Uint8List.fromList(utf8.encode(svg));

  Map<String, dynamic> toJson() => {
        'svg': svg,
        'dataUrl': dataUrl,
        'mimeType': mimeType,
        'size': size,
        'moduleCount': moduleCount,
        'bytes': bytes.length,
      };
}

class QrCodeGenerator {
  QrCodeGenerator._();

  static const int minSize = 96;
  static const int maxSize = 2048;
  static const int minMargin = 0;
  static const int maxMargin = 16;
  static const int maxTextBytes = 1200;

  static QrCodeArtifact generate(QrCodeOptions options) {
    final text = options.text.trim();
    if (text.isEmpty) {
      throw ArgumentError('QR code text must not be empty.');
    }
    final textBytes = utf8.encode(text).length;
    if (textBytes > maxTextBytes) {
      throw ArgumentError(
        'QR code text is too large: $textBytes bytes. '
        'Keep it at or below $maxTextBytes bytes.',
      );
    }

    final size = _boundedInt(
      options.size,
      min: minSize,
      max: maxSize,
      name: 'size',
    );
    final margin = _boundedInt(
      options.margin,
      min: minMargin,
      max: maxMargin,
      name: 'margin',
    );
    final foreground = _normalizedSvgColor(
      options.foregroundColor,
      name: 'foregroundColor',
    );
    final background = _normalizedSvgColor(
      options.backgroundColor,
      name: 'backgroundColor',
      allowTransparent: true,
    );

    final qrCode = QrCode.fromData(
      data: text,
      errorCorrectLevel: _errorCorrectionLevel(options.errorCorrectionLevel),
    );
    final qrImage = QrImage(qrCode);
    final svg = _renderSvg(
      qrImage: qrImage,
      size: size,
      margin: margin,
      foregroundColor: foreground,
      backgroundColor: background,
    );
    return QrCodeArtifact(
      svg: svg,
      dataUrl: 'data:$kQrCodeMimeType;base64,${base64Encode(utf8.encode(svg))}',
      mimeType: kQrCodeMimeType,
      size: size,
      moduleCount: qrImage.moduleCount,
      textBytes: textBytes,
    );
  }

  static int _boundedInt(
    int value, {
    required int min,
    required int max,
    required String name,
  }) {
    if (value < min || value > max) {
      throw ArgumentError('$name must be between $min and $max.');
    }
    return value;
  }

  static int _errorCorrectionLevel(String value) {
    switch (value.trim().toUpperCase()) {
      case 'L':
        return QrErrorCorrectLevel.L;
      case 'M':
        return QrErrorCorrectLevel.M;
      case 'Q':
        return QrErrorCorrectLevel.Q;
      case 'H':
        return QrErrorCorrectLevel.H;
      default:
        throw ArgumentError(
          'errorCorrectionLevel must be one of L, M, Q, or H.',
        );
    }
  }

  static String _normalizedSvgColor(
    String value, {
    required String name,
    bool allowTransparent = false,
  }) {
    final color = value.trim();
    if (allowTransparent && color.toLowerCase() == 'transparent') {
      return 'transparent';
    }
    final valid = RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');
    if (!valid.hasMatch(color)) {
      throw ArgumentError(
        '$name must be a #RGB or #RRGGBB color'
        '${allowTransparent ? ' or transparent' : ''}.',
      );
    }
    return color.toUpperCase();
  }

  static String _renderSvg({
    required QrImage qrImage,
    required int size,
    required int margin,
    required String foregroundColor,
    required String backgroundColor,
  }) {
    final moduleCount = qrImage.moduleCount;
    final viewBoxSize = moduleCount + margin * 2;
    final buffer = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" ')
      ..write('width="$size" height="$size" ')
      ..write('viewBox="0 0 $viewBoxSize $viewBoxSize" ')
      ..write('shape-rendering="crispEdges" role="img">');

    if (backgroundColor != 'transparent') {
      buffer.write(
        '<rect width="$viewBoxSize" height="$viewBoxSize" '
        'fill="$backgroundColor"/>',
      );
    }
    buffer.write('<path fill="$foregroundColor" d="');
    for (var row = 0; row < moduleCount; row++) {
      var col = 0;
      while (col < moduleCount) {
        if (!qrImage.isDark(row, col)) {
          col++;
          continue;
        }
        final start = col;
        while (col < moduleCount && qrImage.isDark(row, col)) {
          col++;
        }
        final x = start + margin;
        final y = row + margin;
        final width = col - start;
        buffer.write('M$x $y h$width v1 H$x z ');
      }
    }
    buffer.write('"/></svg>');
    return buffer.toString();
  }
}
