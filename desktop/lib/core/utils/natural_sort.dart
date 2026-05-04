int naturalCompare(String a, String b) {
  int ia = 0, ib = 0;
  while (ia < a.length && ib < b.length) {
    final ca = a[ia], cb = b[ib];
    final aDigit = ca.codeUnitAt(0) >= 48 && ca.codeUnitAt(0) <= 57;
    final bDigit = cb.codeUnitAt(0) >= 48 && cb.codeUnitAt(0) <= 57;

    if (aDigit && bDigit) {
      int na = 0, nb = 0;
      while (ia < a.length && a[ia].codeUnitAt(0) >= 48 && a[ia].codeUnitAt(0) <= 57) {
        na = na * 10 + a[ia].codeUnitAt(0) - 48;
        ia++;
      }
      while (ib < b.length && b[ib].codeUnitAt(0) >= 48 && b[ib].codeUnitAt(0) <= 57) {
        nb = nb * 10 + b[ib].codeUnitAt(0) - 48;
        ib++;
      }
      if (na != nb) return na.compareTo(nb);
    } else {
      final cmp = ca.toLowerCase().compareTo(cb.toLowerCase());
      if (cmp != 0) return cmp;
      ia++;
      ib++;
    }
  }
  return a.length.compareTo(b.length);
}
