import 'package:flutter/painting.dart';
import 'package:nativa_dom/nativa_dom.dart';

/// Resolves an `img[src]` or CSS `background-image` URL to a Flutter image.
///
/// NativaX never loads network resources implicitly: the host application
/// decides which URLs are allowed and how they are loaded.
typedef NativaXImageResolver = ImageProvider? Function(Element element, String src);

/// Receives layout/style approximations worth surfacing to the host.
typedef NativaXDiagnostic = void Function(String message);
