/// Formatage d'octets en unités lisibles, façon tableau de bord K2000.
///
/// Convention française : o · Ko · Mo · Go (base 1024).
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) {
    return '0 o';
  }
  const units = <String>['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text =
      unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
  return '$text ${units[unit]}';
}

/// « 123.4 / 872.0 Mo » : on ramène le reçu à la même unité que le total et on
/// n'affiche l'unité qu'une fois, pour une lecture stable pendant la descente.
String formatBytesRatio(int received, int total, {int decimals = 1}) {
  if (total <= 0) {
    return formatBytes(received, decimals: decimals);
  }
  const units = <String>['o', 'Ko', 'Mo', 'Go', 'To'];
  var t = total.toDouble();
  var unit = 0;
  while (t >= 1024 && unit < units.length - 1) {
    t /= 1024;
    unit++;
  }
  final divisor = _pow1024(unit);
  final r = received / divisor;
  final d = unit == 0 ? 0 : decimals;
  return '${r.toStringAsFixed(d)} / ${t.toStringAsFixed(d)} ${units[unit]}';
}

/// Débit instantané, « 4.2 Mo/s ».
String formatRate(double bytesPerSecond) {
  if (bytesPerSecond <= 0) {
    return '—';
  }
  return '${formatBytes(bytesPerSecond.round())}/s';
}

double _pow1024(int unit) {
  var result = 1.0;
  for (var i = 0; i < unit; i++) {
    result *= 1024;
  }
  return result;
}
