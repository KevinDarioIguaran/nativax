import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'svg.dart';

/// [ImageProvider] backed by a host-loaded SVG document.
///
/// NativaX never fetches resources by itself: [loader] is supplied by the
/// application (file, asset, HTTP, ...), matching [NativaXImageResolver].
class NativaXSvgImageProvider extends ImageProvider<NativaXSvgImageProvider> {
  NativaXSvgImageProvider(
    this.url,
    this.loader, {
    this.width = 64,
    this.height = 64,
  });

  final String url;
  final Future<Uint8List> Function() loader;
  final int width;
  final int height;

  @override
  Future<NativaXSvgImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NativaXSvgImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      NativaXSvgImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load());
  }

  Future<ImageInfo> _load() async {
    final bytes = await loader();
    final image = await rasterizeSvgBytes(bytes, width: width, height: height);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) =>
      other is NativaXSvgImageProvider &&
      other.url == url &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(url, width, height);

  @override
  String toString() => 'NativaXSvgImageProvider($url)';
}
