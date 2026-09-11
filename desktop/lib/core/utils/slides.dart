/// Groups pages into slides for the reader's double-page mode.
///
/// Two rules shape the result, both matching how a physical book reads:
///
///  * A landscape page is a spread already, so it occupies a slide alone.
///  * Page 0 is the cover and always occupies a slide alone, so it is never
///    paired with the first interior page.
///
/// A page is only paired with its successor when neither is a spread, which is
/// why the page *before* a spread ends up alone too.
///
/// [spreads] is the server-side landscape map and may be shorter than
/// [totalPages] — it arrives after the page count when a chapter is opened from
/// a local manifest — so a missing entry is treated as portrait.
List<List<int>> buildSlides(int totalPages, List<bool> spreads) {
  final slides = <List<int>>[];
  var i = 0;
  while (i < totalPages) {
    final isSpread = i < spreads.length && spreads[i];
    if (isSpread || i == 0) {
      slides.add([i]);
      i++;
    } else {
      final nextIsSpread = (i + 1) < spreads.length && spreads[i + 1];
      if (i + 1 < totalPages && !nextIsSpread) {
        slides.add([i, i + 1]);
        i += 2;
      } else {
        slides.add([i]);
        i++;
      }
    }
  }
  return slides;
}
