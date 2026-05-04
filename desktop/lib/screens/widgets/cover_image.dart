import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CoverImage extends StatelessWidget {
  final String url;
  final Map<String, String> headers;

  /// Overrides the disk-cache key used by [CachedNetworkImage].
  ///
  /// Pass the server's [Media.coverCachePath] so that when the underlying
  /// archive is replaced and the server regenerates the cover, the new cache
  /// key bypasses the stale on-disk entry. Falls back to the URL when null.
  final String? cacheKey;

  /// How the image is inscribed into its box. Defaults to [BoxFit.contain]
  /// so the full cover is always visible without cropping.
  final BoxFit fit;

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const CoverImage({
    super.key,
    required this.url,
    required this.headers,
    this.cacheKey,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey,
      httpHeaders: headers,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.menu_book_outlined, size: 40),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, size: 40),
        ),
      ),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}
