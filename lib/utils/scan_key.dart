/// Shared RFID scan-key helpers.
///
/// Pushpa [Inventoryfragment.addDataToList] / [Searchfragment.addDataToList]
/// look up the reader EPC in a HashMap keyed by TID/barcode. Reader EPCs often
/// have a leading/trailing `"00"` that is not stored on the item — stripping
/// that padding is what makes Java unmatched + global search hit.
String normalizeScanKey(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.toUpperCase();
  if (s.contains(' ')) s = s.replaceAll(' ', '');
  return s;
}

bool isChipEpcHex(String key) {
  return (key.length == 24 || key.length == 32) &&
      RegExp(r'^[0-9A-F]+$').hasMatch(key);
}

/// Strip leading then trailing `"00"`, same order as Pushpa inventory search.
String stripScanKey00(String key) {
  var t = key;
  if (t.length > 2 && t.startsWith('00')) {
    t = t.substring(2);
  }
  if (t.length > 2 && t.endsWith('00')) {
    t = t.substring(0, t.length - 2);
  }
  return t;
}

void addScanKeyVariants(String raw, void Function(String key) add) {
  final key = normalizeScanKey(raw);
  if (key.isEmpty) return;
  add(key);
  final stripped = stripScanKey00(key);
  if (stripped.isNotEmpty && stripped != key) add(stripped);
  if (!key.startsWith('00') && key.length + 2 <= 64) add('00$key');
  if (stripped.isNotEmpty &&
      stripped != key &&
      !stripped.startsWith('00') &&
      stripped.length + 2 <= 64) {
    add('00$stripped');
  }
  if (key.length > 24) add(key.substring(0, 24));
  if (key.length > 32) add(key.substring(0, 32));
}
