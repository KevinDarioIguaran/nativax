import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

/// A decoded 8-bit RGBA raster.
///
/// Only what the visual judge needs is implemented: one image, straight RGBA,
/// row-major, no colour management. Both Chromium and Flutter emit 8-bit
/// non-interlaced PNGs, so the decoder is deliberately strict instead of
/// silently accepting formats it cannot measure.
class RasterImage {
  RasterImage(this.width, this.height, this.rgba)
    : assert(
        rgba.length == width * height * 4,
        'RGBA buffer does not match the raster size',
      );

  final int width;
  final int height;
  final Uint8List rgba;

  int get pixelCount => width * height;

  int red(int x, int y) => rgba[(y * width + x) * 4];
  int green(int x, int y) => rgba[(y * width + x) * 4 + 1];
  int blue(int x, int y) => rgba[(y * width + x) * 4 + 2];
  int alpha(int x, int y) => rgba[(y * width + x) * 4 + 3];

  bool contains(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// Returns the top-left region of this image, clamped to its bounds.
  RasterImage crop(int newWidth, int newHeight) {
    final w = newWidth.clamp(0, width);
    final h = newHeight.clamp(0, height);
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      out.setRange(y * w * 4, (y + 1) * w * 4, rgba, y * width * 4);
    }
    return RasterImage(w, h, out);
  }

  /// Resizes with nearest-neighbour sampling. Only used by the self-check
  /// guard, never by scoring.
  RasterImage nearest(int newWidth, int newHeight) {
    final out = Uint8List(newWidth * newHeight * 4);
    final sx = width / newWidth;
    final sy = height / newHeight;
    for (var y = 0; y < newHeight; y++) {
      final srcY = (y * sy).floor().clamp(0, height - 1);
      for (var x = 0; x < newWidth; x++) {
        final srcX = (x * sx).floor().clamp(0, width - 1);
        final src = (srcY * width + srcX) * 4;
        final dst = (y * newWidth + x) * 4;
        out[dst] = rgba[src];
        out[dst + 1] = rgba[src + 1];
        out[dst + 2] = rgba[src + 2];
        out[dst + 3] = rgba[src + 3];
      }
    }
    return RasterImage(newWidth, newHeight, out);
  }
}

class PngException implements Exception {
  PngException(this.message);
  final String message;
  @override
  String toString() => 'PngException: $message';
}

const List<int> _signature = [137, 80, 78, 71, 13, 10, 26, 10];

/// Decodes an 8-bit, non-interlaced PNG (greyscale, RGB, palette, grey+alpha
/// or RGBA) into [RasterImage].
RasterImage decodePng(Uint8List bytes) {
  if (bytes.length < 8) throw PngException('file is too short');
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _signature[i]) throw PngException('missing PNG signature');
  }
  var offset = 8;
  int? width;
  int? height;
  int colorType = -1;
  int bitDepth = -1;
  var interlace = 0;
  final idat = BytesBuilder(copy: false);
  Uint8List? palette;

  while (offset + 8 <= bytes.length) {
    final length = _readU32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) throw PngException('truncated $type chunk');
    final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
    switch (type) {
      case 'IHDR':
        if (length < 13) throw PngException('invalid IHDR');
        width = _readU32(data, 0);
        height = _readU32(data, 4);
        bitDepth = data[8];
        colorType = data[9];
        if (data[10] != 0)
          throw PngException('unknown compression method ${data[10]}');
        if (data[11] != 0)
          throw PngException('unknown filter method ${data[11]}');
        interlace = data[12];
      case 'PLTE':
        palette = Uint8List.fromList(data);
      case 'IDAT':
        idat.add(data);
      case 'IEND':
        offset = dataEnd + 4;
      default:
        // Unknown ancillary chunks are safe to skip.
        break;
    }
    offset = dataEnd + 4;
    if (type == 'IEND') break;
  }

  if (width == null || height == null || colorType < 0) {
    throw PngException('missing IHDR');
  }
  if (bitDepth != 8) throw PngException('unsupported bit depth $bitDepth');
  if (interlace != 0) throw PngException('interlaced PNGs are not supported');
  if (width <= 0 || height <= 0)
    throw PngException('invalid raster size $width x $height');

  final channels = switch (colorType) {
    0 => 1,
    2 => 3,
    3 => 1,
    4 => 2,
    6 => 4,
    _ => throw PngException('unsupported colour type $colorType'),
  };
  if (colorType == 3 && palette == null)
    throw PngException('palette PNG without PLTE');

  final raw = ZLibDecoder().convert(idat.takeBytes().toList(growable: false));
  final stride = width * channels;
  final expected = (stride + 1) * height;
  if (raw.length < expected) {
    throw PngException(
      'inflated data is ${raw.length} bytes, expected $expected',
    );
  }

  final pixels = Uint8List(stride * height);
  final prior = Uint8List(stride);
  final line = Uint8List(stride);
  var rawOffset = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[rawOffset++];
    line.setRange(0, stride, raw, rawOffset);
    rawOffset += stride;
    for (var x = 0; x < stride; x++) {
      final a = x >= channels ? line[x - channels] : 0;
      final b = prior[x];
      final c = x >= channels ? prior[x - channels] : 0;
      final value = switch (filter) {
        0 => line[x],
        1 => line[x] + a,
        2 => line[x] + b,
        3 => line[x] + ((a + b) >> 1),
        4 => line[x] + _paeth(a, b, c),
        _ => throw PngException('unknown filter $filter on row $y'),
      };
      line[x] = value & 0xff;
    }
    pixels.setRange(y * stride, (y + 1) * stride, line);
    prior.setAll(0, line);
  }

  final rgba = Uint8List(width * height * 4);
  var src = 0;
  var dst = 0;
  for (var i = 0; i < width * height; i++) {
    switch (colorType) {
      case 0:
        final g = pixels[src++];
        rgba[dst++] = g;
        rgba[dst++] = g;
        rgba[dst++] = g;
        rgba[dst++] = 255;
      case 2:
        rgba[dst++] = pixels[src++];
        rgba[dst++] = pixels[src++];
        rgba[dst++] = pixels[src++];
        rgba[dst++] = 255;
      case 3:
        final index = pixels[src++] * 3;
        if (index + 2 >= palette!.length)
          throw PngException('palette index out of range');
        rgba[dst++] = palette[index];
        rgba[dst++] = palette[index + 1];
        rgba[dst++] = palette[index + 2];
        rgba[dst++] = 255;
      case 4:
        final g = pixels[src++];
        rgba[dst++] = g;
        rgba[dst++] = g;
        rgba[dst++] = g;
        rgba[dst++] = pixels[src++];
      case 6:
        rgba[dst++] = pixels[src++];
        rgba[dst++] = pixels[src++];
        rgba[dst++] = pixels[src++];
        rgba[dst++] = pixels[src++];
    }
  }
  return RasterImage(width, height, rgba);
}

/// Encodes [image] as an 8-bit RGBA PNG with filter 0. Used for diff images.
Uint8List encodePng(RasterImage image) {
  final stride = image.width * 4;
  final raw = Uint8List((stride + 1) * image.height);
  for (var y = 0; y < image.height; y++) {
    raw[y * (stride + 1)] = 0;
    raw.setRange(
      y * (stride + 1) + 1,
      (y + 1) * (stride + 1),
      image.rgba,
      y * stride,
    );
  }
  final compressed = ZLibEncoder().convert(raw);
  final out = BytesBuilder(copy: false)
    ..add(_signature)
    ..add(
      _chunk('IHDR', () {
        final b = Uint8List(13);
        _writeU32(b, 0, image.width);
        _writeU32(b, 4, image.height);
        b[8] = 8; // bit depth
        b[9] = 6; // RGBA
        b[10] = 0;
        b[11] = 0;
        b[12] = 0;
        return b;
      }()),
    )
    ..add(_chunk('IDAT', Uint8List.fromList(compressed)))
    ..add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final out = Uint8List(12 + data.length);
  _writeU32(out, 0, data.length);
  out.setRange(4, 8, type.codeUnits);
  out.setRange(8, 8 + data.length, data);
  _writeU32(out, 8 + data.length, _crc32(out, 4, 8 + data.length));
  return out;
}

int _readU32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void _writeU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(Uint8List bytes, int start, int end) {
  var c = 0xffffffff;
  for (var i = start; i < end; i++) {
    c = _crcTable[(c ^ bytes[i]) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}
