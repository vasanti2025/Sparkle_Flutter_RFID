import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../utils/app_dropdown.dart';
import '../utils/scan_key.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/scan_display_list_menu.dart';

class SearchItem {
  final String epc;
  final String itemCode;
  final String productName;
  final String rfid;
  final String tid;
  final String hex;
  String rssi;
  int proximityPercent;
  final List<(int atMs, int percent)> _peakWindow = [];
  int _lastFallMs = 0;

  late final String normEpc;
  late final String normRfid;
  late final String normItemCode;
  late final String normTid;
  late final String normHex;
  /// First real read locks this row. Later RSSI updates must not move it.
  bool positionLocked;
  /// User tapped the row's match button. Scanning must not clear this.
  bool manuallyMatched;

  SearchItem({
    required this.epc,
    required this.itemCode,
    required this.productName,
    required this.rfid,
    this.tid = '',
    this.hex = '',
    this.rssi = '',
    this.proximityPercent = 0,
    this.positionLocked = false,
    this.manuallyMatched = false,
  }) {
    normEpc = normalizeScanKey(epc);
    normRfid = normalizeScanKey(rfid);
    normItemCode = normalizeScanKey(itemCode);
    normTid = normalizeScanKey(tid);
    normHex = normalizeScanKey(hex);
  }

  /// Hold the strongest recent reading. LED blink makes RSSI jump, so the
  /// number rises immediately but only eases down while the gun stays close.
  /// [onlyRaise] keeps the highest percentage reached and ignores weaker reads.
  bool applyStableProximity(String rssi, int rawPercent, {bool onlyRaise = false}) {
    this.rssi = rssi;
    final sample = (rawPercent.clamp(0, 100) / 5).round() * 5;
    if (onlyRaise) {
      if (sample <= proximityPercent) return false;
      proximityPercent = sample;
      return true;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _peakWindow.add((now, sample));
    _peakWindow.removeWhere((e) => now - e.$1 > 4000);
    var peak = 0;
    for (final e in _peakWindow) {
      if (e.$2 > peak) peak = e.$2;
    }
    if (peak >= proximityPercent) {
      if (peak == proximityPercent) return false;
      proximityPercent = peak;
      return true;
    }
    if (now - _lastFallMs < 1200) return false;
    final next = peak > proximityPercent - 5 ? peak : proximityPercent - 5;
    if (next == proximityPercent) return false;
    _lastFallMs = now;
    proximityPercent = next;
    return true;
  }

  void decayTowardZero() {
    if (proximityPercent <= 0) return;
    _peakWindow.clear();
    if (proximityPercent > 75) {
      proximityPercent = 75;
    } else if (proximityPercent > 50) {
      proximityPercent = 50;
    } else if (proximityPercent > 25) {
      proximityPercent = 25;
    } else {
      proximityPercent = 0;
      rssi = '';
    }
  }

  void clearScan() {
    rssi = '';
    proximityPercent = 0;
    positionLocked = false;
    _peakWindow.clear();
  }

  /// Keep the bar where it is across a stop/start. A pause must not look like
  /// the tag left the field.
  void holdProgress() {
    if (proximityPercent <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _peakWindow
      ..clear()
      ..add((now, proximityPercent));
    _lastFallMs = now;
  }
}

/// One Unmatched Search read. Never lowers a percent already on the row.
/// A positive read that would round to 0%, or a chip read with no RSSI, still
/// counts as seen at the smallest bar step (5). Later stronger reads only rise.
bool applyUnmatchedRead(SearchItem item, int proximity, String rssi) {
  if (proximity <= 0) {
    if (item.proximityPercent > 0) return false;
    return item.applyStableProximity(rssi, 5, onlyRaise: true);
  }
  final sample = proximity < 3 ? 3 : proximity;
  return item.applyStableProximity(rssi, sample, onlyRaise: true);
}

/// First row keeps a shared key. A later row must not steal it and hide the first.
bool claimUnmatchedIndexKey(Map<String, int> map, String key, int index) {
  final existing = map[key];
  if (existing != null && existing != index) return false;
  map[key] = index;
  return true;
}

/// Single compact unmatched list shared with inventory — avoids a second 50k copy
/// on 3GB handhelds (Navigator arguments + SearchItem list would OOM/ANR).
class UnmatchedSearchCatalog {
  UnmatchedSearchCatalog._();
  static final UnmatchedSearchCatalog instance = UnmatchedSearchCatalog._();

  final List<SearchItem> items = [];

  /// Keys for the items this Unmatched Search screen is showing.
  /// Save and match-sync use this so other session rows are left out.
  Set<String>? screenKeys;

  /// Scan Display save / list / email — used only by Search Unmatched.
  VoidCallback? onSave;
  void Function(BuildContext dialogContext)? onEmail;
  void Function(String menu)? onSelectMenu;
  VoidCallback? onResumeScan;
  int Function()? matchedCountOf;
  int Function()? unmatchedCountOf;
  int Function()? unlabelledCountOf;

  void clear() {
    items.clear();
    screenKeys = null;
  }

  void clearActions() {
    onSave = null;
    onEmail = null;
    onSelectMenu = null;
    onResumeScan = null;
    matchedCountOf = null;
    unmatchedCountOf = null;
    unlabelledCountOf = null;
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final RfidService _rfidService = RfidService();
  final TextEditingController _searchController = TextEditingController();
  
  StreamSubscription? _tagsSubscription;
  StreamSubscription? _triggerSubscription;
  Timer? _debounceTimer;
  Timer? _uiFlushTimer;
  Timer? _proximityDecayTimer;
  bool _scanBusy = false;

  bool _isInit = false;
  bool _isLoading = false;
  bool _isScanning = false;
  bool _showMenu = false;
  bool _isHandingOff = false;
  int _selectedPower = 30;

  String _listKey = 'normal'; // 'unmatchedItems' or 'normal'
  String _selectedSearchType = 'LabelStock'; // 'LabelStock', 'Order', 'Box'
  String _searchQuery = '';

  List<SearchItem> _searchItems = [];

  // O(1) tag lookup — mirrors Kotlin SearchViewModel.epcToIndex
  final Map<String, int> _tagIndexMap = {};
  final Map<int, int> _lastRssiUpdateMs = {};
  int _lastSearchUiUpdateUs = 0;
  int _lastCatalogUiUpdateUs = 0;
  final Set<int> _dirtyIndices = {};
  final Set<int> _hotSet = {};
  final Set<int> _atMaxProximity = {};
  final List<int> _hotIndices = [];
  final List<int> _visibleOrder = [];
  /// Main unmatched list with the pinned nearby rows removed, so a tag is not shown twice.
  List<int> _mainDisplayOrder = [];
  bool _mainDisplayDirty = true;
  /// Shuffled scan order. RSSI may move a row only until its first read.
  List<int> _displayOrder = [];
  int _orderGen = 0;
  int _shuffledGen = -1;
  bool _rssiOrderDirty = false;
  bool _displayIndexValid = false;
  int _filteredCount = 0;
  /// Unmatched rows that match the current text query. Empty means the whole list.
  final Set<int> _queryScopeIndices = {};
  bool _indexReady = true;
  int _lastRssiSoundMs = 0;
  int _lastRssiSoundId = -1;
  /// Manual matches on this Unmatched Search list. Not tied to scan percentage.
  int _manualMatchedCount = 0;
  _SearchCountFilter _countFilter = _SearchCountFilter.all;
  List<int> _statusOrder = [];
  bool _statusOrderDirty = true;
  /// After a 100% auto-stop, do not auto-stop again until the gun leaves the tag.
  bool _completeAtSessionStart = false;
  final ValueNotifier<int> _nearbyTick = ValueNotifier<int>(0);

  bool get _isLargeUnmatched =>
      _listKey == 'unmatchedItems' && _searchItems.length >= 500;

  bool get _isHomeSearch => _listKey == 'normal';

  /// Home Search scan accepts only this row, so nearby tags are ignored.
  int? _homeScanOnlyIndex;

  /// True after a typed Scan Display search replaced the full unmatched tag set.
  bool _nativeTagsNarrowed = false;
  /// Full unmatched catalog is already on the reader, so Scan must not upload it again.
  bool _unmatchedTagsOnReader = false;
  /// Rows that received a read this scan, including ones already above 0%.
  final Set<int> _unmatchedSeen = {};
  int _unmatchedUnknown = 0;
  int _unmatchedRssiMissing = 0;
  int _unmatchedIndexCollisions = 0;
  int _unmatchedMaxHandlerUs = 0;
  int _unmatchedScanStartedMs = 0;
  int _unmatchedOldestDirtyMs = 0;
  int _unmatchedLastLogMs = 0;
  final Set<String> _unmatchedUnknownEpcs = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_rfidService.preWarmReader());
    });
    _tagsSubscription = _rfidService.tagsWithRssiStream.listen(_onTagScanned);
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _toggleScanning();
    });
    _loadPower();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        final listKey = args['listKey'] as String? ?? 'normal';
        _listKey = listKey;
        if (_listKey == 'unmatchedItems') {
          _isLoading = true;
          _indexReady = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_attachUnmatchedCatalog());
          });
        }
      }
      _isInit = true;
    }
  }

  @override
  void dispose() {
    _tagsSubscription?.cancel();
    _triggerSubscription?.cancel();
    _debounceTimer?.cancel();
    _uiFlushTimer?.cancel();
    _proximityDecayTimer?.cancel();
    _nearbyTick.dispose();
    unawaited(_rfidService.stopInventorySound());
    unawaited(_rfidService.stopSound());
    unawaited(_rfidService.stopScanning());
    unawaited(_rfidService.clearSearchTags());
    if (_listKey == 'unmatchedItems') {
      UnmatchedSearchCatalog.instance.clear();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPower() async {
    // Search / Unmatched Search always start at full range (30).
    final pref = context.read<PrefService>();
    if (pref.searchPower != 30) {
      unawaited(pref.savePower(PrefService.keySearchCount, 30));
    }
    if (mounted) setState(() => _selectedPower = 30);
    unawaited(_rfidService.setPower(30));
  }

  /// Trim + uppercase + strip spaces — matches native EPC keys and stock transfer.
  static String _normScanKey(String value) => normalizeScanKey(value);

  void _indexSearchItem(int i, SearchItem item) {
    void add(String key) {
      addScanKeyVariants(key, (k) {
        if (_listKey == 'unmatchedItems') {
          if (!claimUnmatchedIndexKey(_tagIndexMap, k, i)) {
            _unmatchedIndexCollisions++;
          }
          return;
        }
        _tagIndexMap[k] = i;
      });
    }

    add(item.normEpc);
    add(item.normRfid);
    add(item.normItemCode);
    add(item.normTid);
    add(item.normHex);
  }

  Future<void> _attachUnmatchedCatalog() async {
    // Reuse the catalog inventory already filled — do not copy 50k rows.
    _searchItems = UnmatchedSearchCatalog.instance.items;
    _dedupeSearchItems();
    if (!mounted) return;
    if (_searchItems.isEmpty) {
      setState(() {
        _isLoading = false;
        _indexReady = true;
        _displayIndexValid = false;
      });
      return;
    }
    await _rebuildTagIndexChunked();
    if (!mounted) return;
    if (_unmatchedIndexCollisions > 0) {
      debugPrint(
        'UnmatchedScan index catalog=${_searchItems.length} '
        'keys=${_tagIndexMap.length} collisions=$_unmatchedIndexCollisions',
      );
    }
    if (_tagIndexMap.isNotEmpty) {
      await _rfidService.setSearchTags(_tagIndexMap.keys.toList(growable: false));
      _unmatchedTagsOnReader = true;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _indexReady = true;
      _invalidateDisplayOrder();
      _ensureShuffledOrder();
      _displayIndexValid = false;
    });
    unawaited(_rfidService.prepareForScan());
  }

  Future<void> _rebuildTagIndexChunked() async {
    _tagIndexMap.clear();
    if (_listKey == 'unmatchedItems') _unmatchedIndexCollisions = 0;
    const chunk = 600;
    for (int i = 0; i < _searchItems.length; i++) {
      _indexSearchItem(i, _searchItems[i]);

      if (i > 0 && i % chunk == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }
  }

  void _startProximityDecay() {
    _proximityDecayTimer?.cancel();
    _proximityDecayTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _decayStaleProximity();
    });
  }

  void _stopProximityDecay() {
    _proximityDecayTimer?.cancel();
    _proximityDecayTimer = null;
  }

  /// Drop progress only after the tag has been silent for 2s (out of field).
  /// Inventory gaps of a few hundred ms are normal and must not move the bar.
  /// Stopped scans stay frozen.
  void _decayStaleProximity() {
    if (!_isScanning || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var any = false;
    for (final entry in _lastRssiUpdateMs.entries) {
      final i = entry.key;
      if (i < 0 || i >= _searchItems.length) continue;
      final item = _searchItems[i];
      if (item.proximityPercent <= 0) continue;
      if (now - entry.value < 4000) continue;
      if (_listKey == 'unmatchedItems') {
        // Out of range: leave the top strip. Keep the highest percentage.
        if (!_hotSet.contains(i)) continue;
        _dirtyIndices.add(i);
        any = true;
        continue;
      }
      item.decayTowardZero();
      _dirtyIndices.add(i);
      any = true;
    }
    if (any) _scheduleSearchUiUpdate();
  }

  void _rebuildTagIndex() {
    _tagIndexMap.clear();
    for (int i = 0; i < _searchItems.length; i++) {
      _indexSearchItem(i, _searchItems[i]);
    }
  }

  void _invalidateDisplayOrder() {
    _orderGen++;
    _displayOrder = [];
    _visibleOrder.clear();
    _mainDisplayOrder = [];
    _mainDisplayDirty = true;
    _rssiOrderDirty = false;
    _shuffledGen = -1;
  }

  List<String> _chipKeysOf(SearchItem item) {
    final keys = <String>[];
    void add(String raw) {
      final key = normalizeScanKey(raw);
      if (key.isEmpty) return;
      keys.add(key);
      final stripped = stripScanKey00(key);
      if (stripped.isNotEmpty && stripped != key) keys.add(stripped);
    }

    add(item.rfid);
    add(item.epc);
    add(item.tid);
    return keys;
  }

  /// Drop a later row that is the same RFID, EPC, TID, or item code already listed.
  void _dedupeSearchItems() {
    if (_listKey != 'unmatchedItems' || _searchItems.length < 2) return;
    final codesWithChip = <String>{};
    for (final item in _searchItems) {
      if (_chipKeysOf(item).isEmpty) continue;
      final code = normalizeScanKey(item.itemCode);
      if (code.isNotEmpty) codesWithChip.add(code);
    }
    final seen = <String>{};
    var write = 0;
    for (var read = 0; read < _searchItems.length; read++) {
      final item = _searchItems[read];
      final keys = _chipKeysOf(item);
      final code = normalizeScanKey(item.itemCode);
      if (keys.isEmpty) {
        if (code.isNotEmpty &&
            (codesWithChip.contains(code) || !seen.add('code:$code'))) {
          continue;
        }
      } else {
        var known = false;
        for (final key in keys) {
          if (seen.contains(key)) {
            known = true;
            break;
          }
        }
        if (known) continue;
        seen.addAll(keys);
        if (code.isNotEmpty) seen.add('code:$code');
      }
      if (write != read) _searchItems[write] = item;
      write++;
    }
    if (write < _searchItems.length) {
      _searchItems.removeRange(write, _searchItems.length);
    }
  }

  /// One shuffle per result set. Does not reorder the shared unmatched catalog.
  void _ensureShuffledOrder() {
    if (_shuffledGen == _orderGen && _displayOrder.length == _searchItems.length) {
      return;
    }
    _displayOrder = List<int>.generate(_searchItems.length, (i) => i)..shuffle();
    _shuffledGen = _orderGen;
  }

  /// Stronger unread tags move ahead of other unread tags, then lock.
  void _placeByRssiThenLock(List<int> order) {
    if (order.isEmpty) return;
    final live = <int>[];
    for (final id in order) {
      if (id < 0 || id >= _searchItems.length) continue;
      final item = _searchItems[id];
      if (!item.positionLocked && item.proximityPercent > 0) live.add(id);
    }
    if (live.isEmpty) return;
    if (live.length == 1 && order.length == 1) {
      _searchItems[live.first].positionLocked = true;
      return;
    }
    if (live.length > 1) {
      live.sort((a, b) =>
          _searchItems[b].proximityPercent.compareTo(_searchItems[a].proximityPercent));
    }
    for (final id in live) {
      var pos = order.indexOf(id);
      if (pos < 0) continue;
      final strength = _searchItems[id].proximityPercent;
      while (pos > 0) {
        final ahead = order[pos - 1];
        if (ahead < 0 || ahead >= _searchItems.length) break;
        final aheadItem = _searchItems[ahead];
        if (aheadItem.positionLocked) break;
        if (aheadItem.proximityPercent > strength) break;
        order[pos] = ahead;
        order[pos - 1] = id;
        pos--;
      }
      _searchItems[id].positionLocked = true;
    }
  }

  void _applyRssiPriority() {
    final needsShuffle =
        _shuffledGen != _orderGen || _displayOrder.length != _searchItems.length;
    if (!_rssiOrderDirty && !needsShuffle) return;
    if (needsShuffle) _ensureShuffledOrder();
    if (_rssiOrderDirty && _displayOrder.isNotEmpty) {
      _placeByRssiThenLock(_displayOrder);
    }
    _rssiOrderDirty = false;
  }

  void _rebuildNearbyOnly() {
    final touched = List<int>.of(_dirtyIndices);
    for (final i in touched) {
      if (i < 0 || i >= _searchItems.length) continue;
      final prox = _searchItems[i].proximityPercent;
      if (prox > 0) {
        final seenAt = _lastRssiUpdateMs[i] ?? 0;
        final stillInRange = DateTime.now().millisecondsSinceEpoch - seenAt < 4000;
        if (_listKey == 'unmatchedItems' && !stillInRange) {
          _hotSet.remove(i);
        } else {
          _hotSet.add(i);
        }
      } else {
        _hotSet.remove(i);
      }
      if (prox >= 100) {
        _atMaxProximity.add(i);
      } else {
        _atMaxProximity.remove(i);
      }
    }
    _dirtyIndices.clear();
    _unmatchedOldestDirtyMs = 0;
    _applyRssiPriority();
    if (_listKey != 'unmatchedItems') return;
    _refreshUpsideIndices(touched);
  }

  /// Tags just read stay in the top strip, even when older rows are locked.
  void _refreshUpsideIndices([List<int>? touched]) {
    if (_hotSet.isEmpty) {
      if (_hotIndices.isEmpty) return;
      _hotIndices.clear();
      _mainDisplayDirty = true;
      return;
    }
    final next = <int>[];
    final seen = <int>{};
    void consider(int i) {
      if (next.length >= 8) return;
      if (!seen.add(i)) return;
      if (i < 0 || i >= _searchItems.length) return;
      if (!_hotSet.contains(i)) return;
      if (_searchItems[i].proximityPercent <= 0) return;
      if (!_inCurrentSearchView(i)) return;
      next.add(i);
    }

    if (touched != null && touched.isNotEmpty) {
      final newest = List<int>.of(touched);
      newest.sort((a, b) =>
          (_lastRssiUpdateMs[b] ?? 0).compareTo(_lastRssiUpdateMs[a] ?? 0));
      for (final i in newest) {
        consider(i);
      }
      for (final i in _hotIndices) {
        consider(i);
      }
    } else {
      final ranked = <int>[];
      for (final i in _hotSet) {
        if (i < 0 || i >= _searchItems.length) continue;
        if (_searchItems[i].proximityPercent <= 0) continue;
        if (!_inCurrentSearchView(i)) continue;
        ranked.add(i);
      }
      ranked.sort((a, b) =>
          (_lastRssiUpdateMs[b] ?? 0).compareTo(_lastRssiUpdateMs[a] ?? 0));
      for (final i in ranked) {
        consider(i);
        if (next.length >= 8) break;
      }
    }
    final sameSet = _sameIndexSet(_hotIndices, next);
    if (_sameIndexList(_hotIndices, next)) return;
    _hotIndices
      ..clear()
      ..addAll(next);
    if (!sameSet) _mainDisplayDirty = true;
  }

  bool _inCurrentSearchView(int index) {
    final query = _searchQuery.trim().toUpperCase().replaceAll(' ', '');
    if (query.isEmpty) return true;
    final item = _searchItems[index];
    return item.normItemCode.contains(query) ||
        item.normRfid.contains(query) ||
        item.normEpc.contains(query) ||
        item.normTid.contains(query) ||
        item.normHex.contains(query);
  }

  bool _sameIndexList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _sameIndexSet(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    if (_sameIndexList(a, b)) return true;
    final left = a.toSet();
    for (final i in b) {
      if (!left.contains(i)) return false;
    }
    return true;
  }

  int _nearbyPinnedCount() {
    if (_listKey != 'unmatchedItems' || _countFilter != _SearchCountFilter.all) {
      return 0;
    }
    final n = _hotIndices.length;
    if (n <= 0) return 0;
    return n > 8 ? 8 : n;
  }

  void _ensureMainDisplayOrder() {
    _ensureShuffledOrder();
    final pinned = _nearbyPinnedCount();
    if (pinned == 0) return;
    if (!_mainDisplayDirty && _mainDisplayOrder.isNotEmpty) return;
    final skip = <int>{};
    for (var i = 0; i < pinned; i++) {
      skip.add(_hotIndices[i]);
    }
    final List<int> source;
    if (_searchQuery.trim().isEmpty) {
      source = _displayOrder;
    } else {
      if (!_displayIndexValid) _rebuildDisplayIndices();
      source = _visibleOrder;
    }
    final next = <int>[];
    for (final i in source) {
      if (skip.contains(i)) continue;
      next.add(i);
    }
    _mainDisplayOrder = next;
    _mainDisplayDirty = false;
  }

  /// Rows under the top strip. The strip itself is not repeated here.
  int _unmatchedOpenCount() {
    if (_nearbyPinnedCount() == 0) {
      if (_isLargeUnmatched && _searchQuery.trim().isEmpty) {
        return _searchItems.length;
      }
      if (!_displayIndexValid) _rebuildDisplayIndices();
      return _filteredCount;
    }
    _ensureMainDisplayOrder();
    return _mainDisplayOrder.length;
  }

  SearchItem? _itemAtUnmatchedOpen(int index) {
    if (_nearbyPinnedCount() == 0) {
      if (_searchQuery.trim().isEmpty) return _itemAtDisplay(index);
      return _tryDisplayItemAt(index);
    }
    _ensureMainDisplayOrder();
    if (index < 0 || index >= _mainDisplayOrder.length) return null;
    final i = _mainDisplayOrder[index];
    if (i < 0 || i >= _searchItems.length) return null;
    return _searchItems[i];
  }

  void _flushPendingSearchUpdates() {
    if (_dirtyIndices.isEmpty) return;
    if (!mounted) return;
    final uiDelayMs = _unmatchedOldestDirtyMs == 0
        ? 0
        : DateTime.now().millisecondsSinceEpoch - _unmatchedOldestDirtyMs;
    _rebuildNearbyOnly();
    // Percent ticks must not rebuild the row index. That walk was running on
    // the tag callback and let a burst of reads stall the screen.
    if (_listKey != 'unmatchedItems') _displayIndexValid = false;
    if (_listKey == 'unmatchedItems') {
      _nearbyTick.value++;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    final catalogUs = _isLargeUnmatched && _searchQuery.trim().isEmpty ? 120000 : 0;
    if (catalogUs == 0 ||
        _lastCatalogUiUpdateUs == 0 ||
        now - _lastCatalogUiUpdateUs >= catalogUs) {
      _lastCatalogUiUpdateUs = now;
      setState(() {});
    }
    if (_listKey == 'unmatchedItems') {
      _logUnmatchedScanProgress(uiDelayMs);
      _checkAutoStopSearch();
    }
  }

  /// Unmatched Search only: stop when every visible item is at 100%.
  /// Global Search never auto-stops at 100%.
  void _checkAutoStopSearch() {
    if (_listKey != 'unmatchedItems') return;
    if (!_isScanning || _scanBusy) return;
    if (_searchItems.isEmpty) return;
    if (_completeAtSessionStart) {
      if (!_visibleItemsAllAtMax()) {
        _completeAtSessionStart = false;
      }
      return;
    }
    if (!_everyExpectedItemFound()) return;
    _showToast('All Items Found');
    unawaited(_stopSearchScan());
  }

  /// Every row on this Unmatched Search screen is at 100%. A partial batch
  /// must not count, even if the on-screen filter is stale.
  bool _everyExpectedItemFound() {
    if (_listKey != 'unmatchedItems') return _visibleItemsAllAtMax();
    if (_searchItems.isEmpty) return false;
    if (_searchQuery.trim().isEmpty) {
      for (final item in _searchItems) {
        if (item.proximityPercent < 100) return false;
      }
      return true;
    }
    if (!_displayIndexValid) _rebuildDisplayIndices();
    if (_queryScopeIndices.isEmpty) return false;
    for (final i in _queryScopeIndices) {
      if (i < 0 || i >= _searchItems.length) return false;
      if (_searchItems[i].proximityPercent < 100) return false;
    }
    return true;
  }

  bool _visibleItemsAllAtMax() {
    if (_searchItems.isEmpty) return false;
    if (_isLargeUnmatched && _searchQuery.trim().isEmpty) {
      for (final item in _searchItems) {
        if (item.proximityPercent < 100) return false;
      }
      return true;
    }
    if (!_displayIndexValid) _rebuildDisplayIndices();
    if (_filteredCount <= 0) return false;
    for (var i = 0; i < _filteredCount; i++) {
      final item = _tryDisplayItemAt(i);
      if (item == null || item.proximityPercent < 100) return false;
    }
    return true;
  }

  Future<void> _stopSearchScan() async {
    if (!_isScanning && !_rfidService.isScanning) return;
    _scanBusy = true;
    try {
      if (_listKey == 'unmatchedItems') {
        _uiFlushTimer?.cancel();
        _uiFlushTimer = null;
        _flushPendingSearchUpdates();
        _logUnmatchedScanSummary('stop');
      }
      _stopProximityDecay();
      _homeScanOnlyIndex = null;
      await _rfidService.stopScanning();
      await _rfidService.stopInventorySound();
      await _rfidService.stopSound();
      if (mounted) {
        _displayIndexValid = false;
        setState(() => _isScanning = false);
        _nearbyTick.value++;
      }
    } finally {
      _scanBusy = false;
    }
  }

  void _scheduleSearchUiUpdate() {
    // Unmatched Search paints once per frame. A setState inside the tag
    // callback was blocking the reader stream, so later chips in a burst
    // never reached the list.
    if (_listKey == 'unmatchedItems') {
      _uiFlushTimer ??= Timer(const Duration(milliseconds: 16), () {
        _uiFlushTimer = null;
        _lastSearchUiUpdateUs = DateTime.now().microsecondsSinceEpoch;
        _flushPendingSearchUpdates();
      });
      return;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    final minUs = _isLargeUnmatched ? 16000 : 8000;
    if (_lastSearchUiUpdateUs == 0 ||
        now - _lastSearchUiUpdateUs >= minUs) {
      _lastSearchUiUpdateUs = now;
      _uiFlushTimer?.cancel();
      _flushPendingSearchUpdates();
    } else {
      _uiFlushTimer ??= Timer(Duration(microseconds: minUs), () {
        _uiFlushTimer = null;
        _lastSearchUiUpdateUs = DateTime.now().microsecondsSinceEpoch;
        _flushPendingSearchUpdates();
      });
    }
  }

  SearchItem _searchItemFromBulk(BulkItem item) {
    final epcValue = item.epc.isNotEmpty
        ? item.epc
        : (item.rfid.isNotEmpty
            ? item.rfid
            : (item.itemCode.isNotEmpty ? item.itemCode : ''));
    return SearchItem(
      epc: epcValue,
      itemCode: item.itemCode,
      productName: item.productName,
      rfid: item.rfid,
      tid: item.tid,
      hex: item.box,
    );
  }

  /// Matches Sparkle SearchViewModel + native [playRssiSearchSound] buckets:
  /// lower |RSSI| = closer (stronger signal), higher |RSSI| = farther.
  int convertRssiToProximity(String rssi) {
    try {
      final raw = rssi.trim();
      if (raw.isEmpty) return -1;
      final rssiValue = double.parse(raw);
      if (rssiValue == 0) return -1;
      final magnitude = rssiValue.abs();
      return (((80 - magnitude).clamp(0.0, 40.0)) * 100 / 40).toInt().clamp(0, 100);
    } catch (_) {
      return -1;
    }
  }

  Color getColorByPercentage(int percent) {
    if (percent <= 25) return Colors.red;
    if (percent <= 50) return Colors.yellow[700]!;
    if (percent <= 75) return Colors.blue;
    return Colors.green;
  }

  /// Same buckets as native playRssiSearchSound. Percent is the fallback when
  /// the last RSSI text was cleared but the bar is still showing.
  int _soundIdForRssi(String rssi, int percent) {
    final rssiAbs = double.tryParse(rssi.trim())?.abs() ?? 0;
    if (rssiAbs > 0 && rssiAbs < 50) return 4;
    if (rssiAbs > 50 && rssiAbs < 60) return 2;
    if (rssiAbs > 60 && rssiAbs < 70) return 5;
    if (rssiAbs > 70) return 1;
    if (percent >= 75) return 4;
    if (percent >= 50) return 2;
    if (percent >= 25) return 5;
    if (percent > 0) return 1;
    return -1;
  }

  /// Refresh timestamps so decay does not wipe bars the moment scanning resumes.
  ({String rssi, int percent})? _holdCurrentSearchProgress() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var bestPct = 0;
    var bestRssi = '';
    var any = false;
    _hotSet.removeWhere((i) =>
        i < 0 || i >= _searchItems.length || _searchItems[i].proximityPercent <= 0);
    _atMaxProximity.removeWhere((i) =>
        i < 0 || i >= _searchItems.length || _searchItems[i].proximityPercent < 100);
    for (var i = 0; i < _searchItems.length; i++) {
      final item = _searchItems[i];
      if (item.proximityPercent <= 0) continue;
      any = true;
      item.holdProgress();
      if (_listKey == 'unmatchedItems') {
        // Keep the current top strip. Rows that already left range stay below.
        if (_hotSet.contains(i)) _lastRssiUpdateMs[i] = now;
      } else {
        _lastRssiUpdateMs[i] = now;
        _hotSet.add(i);
      }
      if (item.proximityPercent >= 100) {
        _atMaxProximity.add(i);
      }
      if (item.proximityPercent > bestPct) {
        bestPct = item.proximityPercent;
        bestRssi = item.rssi;
      }
    }
    if (!any) return null;
    if (_listKey == 'unmatchedItems') {
      _refreshUpsideIndices();
      _nearbyTick.value++;
    }
    return (rssi: bestRssi, percent: bestPct);
  }

  void _playRssiSearchSound(String rssi) {
    final rssiAbs = double.tryParse(rssi.trim())?.abs() ?? 0;
    final id = rssiAbs > 0 && rssiAbs < 50
        ? 4
        : rssiAbs > 50 && rssiAbs < 60
            ? 2
            : rssiAbs > 60 && rssiAbs < 70
                ? 5
                : rssiAbs > 70
                    ? 1
                    : -1;
    if (id == -1) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id == _lastRssiSoundId && now - _lastRssiSoundMs < 40) return;
    _lastRssiSoundMs = now;
    _lastRssiSoundId = id;
    unawaited(_rfidService.playSound(id));
  }

  void _beginUnmatchedScanLog() {
    _unmatchedUnknown = 0;
    _unmatchedRssiMissing = 0;
    _unmatchedMaxHandlerUs = 0;
    _unmatchedOldestDirtyMs = 0;
    _unmatchedUnknownEpcs.clear();
    _unmatchedSeen.clear();
    for (var i = 0; i < _searchItems.length; i++) {
      if (_searchItems[i].proximityPercent > 0) _unmatchedSeen.add(i);
    }
    _unmatchedScanStartedMs = DateTime.now().millisecondsSinceEpoch;
    _unmatchedLastLogMs = _unmatchedScanStartedMs;
    debugPrint(
      'UnmatchedScan start catalog=${_searchItems.length} '
      'alreadySeen=${_unmatchedSeen.length}',
    );
  }

  void _noteUnmatchedUnknown(String epc) {
    _unmatchedUnknown++;
    if (!_unmatchedUnknownEpcs.add(epc)) return;
    debugPrint('UnmatchedScan received-not-displayed epc=$epc');
  }

  void _applyUnmatchedTag(
    int index,
    SearchItem item,
    String epc,
    int proximity,
    String rssi,
    int now,
  ) {
    final started = DateTime.now().microsecondsSinceEpoch;
    if (proximity <= 0) _unmatchedRssiMissing++;
    final changed = applyUnmatchedRead(item, proximity, rssi);
    final first = _unmatchedSeen.add(index);
    if (first) {
      debugPrint(
        'UnmatchedScan processed epc=$epc item=${item.itemCode} '
        'percent=${item.proximityPercent}',
      );
    }
    final reentered = !_hotSet.contains(index);
    if (changed || first || reentered) {
      _dirtyIndices.add(index);
      if (_unmatchedOldestDirtyMs == 0) _unmatchedOldestDirtyMs = now;
      if (!item.positionLocked) {
        _rssiOrderDirty = true;
      }
      _scheduleSearchUiUpdate();
    }
    final elapsed = DateTime.now().microsecondsSinceEpoch - started;
    if (elapsed > _unmatchedMaxHandlerUs) _unmatchedMaxHandlerUs = elapsed;
  }

  void _logUnmatchedScanProgress(int uiDelayMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_unmatchedLastLogMs != 0 && now - _unmatchedLastLogMs < 1000) return;
    _unmatchedLastLogMs = now;
    debugPrint(
      'UnmatchedScan +${now - _unmatchedScanStartedMs}ms '
      'seen=${_unmatchedSeen.length}/${_searchItems.length} '
      'uiDelay=${uiDelayMs}ms unknown=$_unmatchedUnknown '
      'rssiMissing=$_unmatchedRssiMissing '
      'maxHandlerUs=$_unmatchedMaxHandlerUs',
    );
  }

  void _logUnmatchedScanSummary(String phase) {
    final missing = <String>[];
    for (var i = 0; i < _searchItems.length; i++) {
      if (_unmatchedSeen.contains(i)) continue;
      final code = _searchItems[i].itemCode.trim();
      missing.add(code.isEmpty ? _searchItems[i].rfid : code);
    }
    final elapsed = _unmatchedScanStartedMs == 0
        ? 0
        : DateTime.now().millisecondsSinceEpoch - _unmatchedScanStartedMs;
    debugPrint(
      'UnmatchedScan $phase +${elapsed}ms '
      'catalog=${_searchItems.length} seen=${_unmatchedSeen.length} '
      'notReceived=${missing.length} receivedNotDisplayed=$_unmatchedUnknown '
      'rssiMissing=$_unmatchedRssiMissing '
      'collisions=$_unmatchedIndexCollisions '
      'maxHandlerUs=$_unmatchedMaxHandlerUs '
      'notReceivedCodes=${missing.take(48).join(",")}'
      '${_unmatchedUnknownEpcs.isEmpty ? "" : " receivedNotDisplayedEpcs=${_unmatchedUnknownEpcs.join(",")}"}',
    );
  }

  void _onTagScanned(Map<String, dynamic> tagEvent) {
    try {
      if (!_isScanning) return;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;

      final epc = _normScanKey(tagEvent['epc'] as String? ?? '');
      final rssi = (tagEvent['rssi'] as String? ?? '').trim();
      if (epc.isEmpty) return;

      final proximity = convertRssiToProximity(rssi);

      final now = DateTime.now().millisecondsSinceEpoch;
      var index = _tagIndexMap[epc];
      if (index == null) {
        final stripped = stripScanKey00(epc);
        if (stripped != epc) index = _tagIndexMap[stripped];
      }
      if (index == null && epc.length > 24) {
        index = _tagIndexMap[epc.substring(0, 24)];
      }
      if (index == null && epc.length > 32) {
        index = _tagIndexMap[epc.substring(0, 32)];
      }
      if (index == null && !epc.startsWith('00') && epc.length + 2 <= 64) {
        index = _tagIndexMap['00$epc'];
      }
      if (index == null || index < 0 || index >= _searchItems.length) {
        if (_listKey == 'unmatchedItems') _noteUnmatchedUnknown(epc);
        return;
      }
      if (_homeScanOnlyIndex != null && index != _homeScanOnlyIndex) return;
      if (_listKey == 'unmatchedItems' &&
          _searchQuery.trim().isNotEmpty &&
          !_queryScopeIndices.contains(index)) {
        return;
      }

      _lastRssiUpdateMs[index] = now;
      final item = _searchItems[index];
      if (_listKey == 'unmatchedItems') {
        _applyUnmatchedTag(index, item, epc, proximity, rssi, now);
        return;
      }
      // LED reads often report RSSI 0. Keep the last percent; do not flash 50%.
      if (proximity < 0) return;
      final prev = item.proximityPercent;
      final changed = item.applyStableProximity(
        rssi,
        proximity,
        onlyRaise: false,
      );
      final reentered = _listKey == 'unmatchedItems' && !_hotSet.contains(index);
      if (changed || reentered) {
        _dirtyIndices.add(index);
        if (!item.positionLocked) {
          _rssiOrderDirty = true;
          _lastSearchUiUpdateUs = 0;
        } else if (prev == 0) {
          _lastSearchUiUpdateUs = 0;
        }
        _scheduleSearchUiUpdate();
      }
    } catch (e) {
      debugPrint('Search tag handler: $e');
    }
  }

  void _toggleScanning() async {
    if (_isHandingOff) return;
    if (_scanBusy) return;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    if (_isScanning) {
      await _stopSearchScan();
      return;
    }

    if (!_indexReady) {
      _showToast(context.sRead.pleaseWaitItemsLoading);
      return;
    }

    if (_isLargeUnmatched) {
      if (_searchItems.isEmpty) {
        _showToast(context.sRead.noItemsToSearch);
        return;
      }
    } else {
      if (!_displayIndexValid) _rebuildDisplayIndices();
      if (_filteredCount <= 0) {
        _showToast(context.sRead.noItemsToSearch);
        return;
      }
    }

    _scanBusy = true;
    try {
      List<String>? tagsToSend;
      if (!(_isLargeUnmatched && _searchQuery.trim().isEmpty)) {
        final cleanTags = _collectSearchTags();
        if (cleanTags.isEmpty) {
          _showToast(context.sRead.noSearchableIdentifiersFound);
          return;
        }
        tagsToSend = cleanTags;
      }

      _completeAtSessionStart = _visibleItemsAllAtMax();
      final held = _holdCurrentSearchProgress();
      setState(() => _isScanning = true);
      if (held == null) {
        unawaited(_rfidService.playBeep());
        _atMaxProximity.clear();
        _hotSet.clear();
        _hotIndices.clear();
      }
      _lastSearchUiUpdateUs = 0;
      _lastCatalogUiUpdateUs = 0;
      _dirtyIndices.clear();
      _displayIndexValid = false;
      if (_listKey == 'unmatchedItems') _beginUnmatchedScanLog();
      _startProximityDecay();

      final List<String> ledEpcs;
      final String ledMode;
      final homeItem = _singleHomeSearchItem();
      if (homeItem != null) {
        final onlyIndex = _searchItems.indexOf(homeItem);
        _homeScanOnlyIndex = onlyIndex >= 0 ? onlyIndex : null;
        final onlyTags = _tagsForOneItem(homeItem);
        if (onlyTags.isEmpty) {
          _homeScanOnlyIndex = null;
          _stopProximityDecay();
          if (mounted) setState(() => _isScanning = false);
          _showToast(context.sRead.noSearchableIdentifiersFound);
          return;
        }
        tagsToSend = onlyTags;
        // RFID code is what the gun reads. The epc column is often TID, and
        // filtering that as EPC leaves the searched tag dark.
        final chip = _oneChipEpc(homeItem);
        ledEpcs = chip == null ? const <String>[] : <String>[chip];
        // Always filter mode so a live hit can still turn this one LED solid.
        ledMode = 'filter';
      } else {
        final listed = _particularListedItem();
        if (listed != null) {
          final onlyIndex = _searchItems.indexOf(listed);
          _homeScanOnlyIndex = onlyIndex >= 0 ? onlyIndex : null;
          final onlyTags = _tagsForOneItem(listed);
          if (onlyTags.isEmpty) {
            _homeScanOnlyIndex = null;
            _stopProximityDecay();
            if (mounted) setState(() => _isScanning = false);
            _showToast(context.sRead.noSearchableIdentifiersFound);
            return;
          }
          tagsToSend = onlyTags;
          _nativeTagsNarrowed = true;
          final chip = _oneChipEpc(listed);
          ledEpcs = chip == null ? const <String>[] : <String>[chip];
          ledMode = 'filter';
        } else {
          // The open list only. Never 'all' — that lights every tag in range.
          _homeScanOnlyIndex = null;
          final narrowed = _searchQuery.trim().isNotEmpty;
          if (tagsToSend == null &&
            (narrowed || _nativeTagsNarrowed || !_isLargeUnmatched)) {
            tagsToSend = _collectSearchTags();
          }
          _nativeTagsNarrowed = narrowed;
          if (narrowed) _unmatchedTagsOnReader = false;
          // Only LED rows on this list. An empty filter lights every LED in range.
          ledEpcs = _listKey == 'unmatchedItems'
              ? _collectInventoryLedEpcs()
              : const <String>[];
          ledMode = 'list';
        }
      }
      if (_listKey == 'unmatchedItems' &&
          _searchQuery.trim().isEmpty &&
          _unmatchedTagsOnReader &&
          !_nativeTagsNarrowed) {
        tagsToSend = null;
      }
      final started = await _rfidService.startSearchScanning(
        power: _selectedPower.clamp(1, 30),
        searchTags: tagsToSend,
        ledEpcs: ledEpcs,
        ledMode: ledMode,
        strictLed: true,
        skipBleProbe: _listKey == 'unmatchedItems',
      );

      if (!mounted) return;
      if (started && held != null) {
        final soundId = _soundIdForRssi(held.rssi, held.percent);
        if (soundId > 0) {
          unawaited(_rfidService.primeSearchSound(soundId));
        }
      }
      if (!started) {
        _stopProximityDecay();
        setState(() => _isScanning = false);
        await _rfidService.stopSound();
        await _rfidService.stopScanning();
        if (!mounted) return;
        _showToast(context.sRead.failedToStartRfidScanner);
      }
    } catch (e) {
      if (mounted) {
        _stopProximityDecay();
        setState(() => _isScanning = false);
        unawaited(_rfidService.stopSound());
        _showToast(context.sRead.failedToStartRfidScanner);
      }
    } finally {
      _scanBusy = false;
    }
  }

  void _onQueryChanged(String val) {
    _searchQuery = val;
    _displayIndexValid = false;
    _statusOrderDirty = true;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (_listKey == 'normal') {
      setState(() {});
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        _performSearch(val);
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _mainDisplayDirty = true;
      _refreshUpsideIndices();
      setState(() {});
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchItems.clear();
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<SearchItem> results = [];
      
      if (_selectedSearchType == 'LabelStock') {
        final dbService = Provider.of<DbService>(context, listen: false);
        final items = await dbService.searchItemsExact(trimmed);

        for (var item in items) {
          results.add(_searchItemFromBulk(item));
        }
      } else if (_selectedSearchType == 'Order') {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
        final clientCode = dashboardViewModel.employee?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          final orders = await apiService.searchOrdersByRfid(clientCode, trimmed);
          for (var order in orders) {
            final items = order['CustomOrderItem'] as List? ?? [];
            final isOrderLevelMatch =
                order['CustomOrderId']?.toString() == trimmed ||
                order['Id']?.toString() == trimmed ||
                (order['OrderNo'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                (order['RfidCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                (order['TidNumber'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase();

            final matchedItems = isOrderLevelMatch
                ? items
                : items.where((item) =>
                    (item['RFIDCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                    (item['ItemCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                    (item['TIDNumber'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase()
                  ).toList();

            for (var item in matchedItems) {
              final rfid = (item['RFIDCode'] as String? ?? '').trim();
              final tid = (item['TIDNumber'] as String? ?? '').trim();
              final code = (item['ItemCode'] as String? ?? '').trim();
              final prodName = (item['ProductName'] as String? ?? '').trim();
              
              final parentRfid = (order['RfidCode'] as String? ?? '').trim();
              final parentTid = (order['TidNumber'] as String? ?? '').trim();
              
              final finalRfid = rfid.isNotEmpty ? rfid : parentRfid;
              final finalTid = tid.isNotEmpty ? tid : parentTid;
              
              final searchKey = finalTid.isNotEmpty
                  ? finalTid
                  : (finalRfid.isNotEmpty ? finalRfid : code);

              results.add(SearchItem(
                epc: searchKey,
                itemCode: code,
                productName: prodName,
                rfid: finalRfid,
                tid: finalTid,
              ));
            }
          }
        }
      } else if (_selectedSearchType == 'Box') {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
        final clientCode = dashboardViewModel.employee?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          final data = await apiService.getBoxDetailsByRfidCode(clientCode, trimmed);
          if (data != null && data['Success'] == true) {
            final boxes = data['Boxes'] as List? ?? [];
            final products = data['Products'] as List? ?? [];
            
            for (var entry in boxes) {
              final boxProducts = entry['Products'] as List? ?? [];
              for (var p in boxProducts) {
                final rfid = (p['RfidCode'] as String? ?? '').trim();
                final tid = (p['TidNumber'] as String? ?? '').trim();
                final hex = (p['HexCode'] as String? ?? '').trim();
                final code = (p['ItemCode'] as String? ?? '').trim();
                final prodName = (p['ProductName'] as String? ?? p['ProductTitle'] as String? ?? '').trim();
                
                final searchKey = tid.isNotEmpty ? tid : (hex.isNotEmpty ? hex : (rfid.isNotEmpty ? rfid : code));
                results.add(SearchItem(
                  epc: searchKey,
                  itemCode: code,
                  productName: prodName,
                  rfid: rfid,
                  tid: tid,
                  hex: hex,
                ));
              }
            }
            
            for (var p in products) {
              final rfid = (p['RfidCode'] as String? ?? '').trim();
              final tid = (p['TidNumber'] as String? ?? '').trim();
              final hex = (p['HexCode'] as String? ?? '').trim();
              final code = (p['ItemCode'] as String? ?? '').trim();
              final prodName = (p['ProductName'] as String? ?? p['ProductTitle'] as String? ?? '').trim();
              
              final searchKey = tid.isNotEmpty ? tid : (hex.isNotEmpty ? hex : (rfid.isNotEmpty ? rfid : code));
              results.add(SearchItem(
                epc: searchKey,
                itemCode: code,
                productName: prodName,
                rfid: rfid,
                tid: tid,
                hex: hex,
              ));
            }
          }
        }
      }

      setState(() {
        _searchItems = results;
        _rebuildTagIndex();
        _invalidateDisplayOrder();
        _displayIndexValid = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showToast(context.sRead.searchError(e));
    }
  }

  /// Scan Display Search: one visible row when the query names a single tag.
  SearchItem? _particularListedItem() {
    if (_isHomeSearch || _searchQuery.trim().isEmpty || _searchItems.isEmpty) {
      return null;
    }
    if (!_displayIndexValid) _rebuildDisplayIndices();
    if (_filteredCount == 1) return _tryDisplayItemAt(0);
    final query = _normScanKey(_searchQuery);
    SearchItem? hit;
    for (final item in _searchItems) {
      if (item.normItemCode == query ||
          item.normRfid == query ||
          item.normEpc == query ||
          item.normTid == query ||
          item.normHex == query) {
        if (hit != null) return null;
        hit = item;
      }
    }
    return hit;
  }

  /// Home Search: the one row the user typed (for example item code SP24).
  SearchItem? _singleHomeSearchItem() {
    if (!_isHomeSearch || _searchItems.isEmpty) return null;
    final query = _normScanKey(_searchQuery);
    if (query.isNotEmpty) {
      for (final item in _searchItems) {
        if (item.normItemCode == query ||
            item.normRfid == query ||
            item.normEpc == query ||
            item.normTid == query ||
            item.normHex == query) {
          return item;
        }
      }
    }
    return _searchItems.first;
  }

  List<String> _tagsForOneItem(SearchItem item) {
    final tags = <String>{};
    addScanKeyVariants(item.epc, tags.add);
    addScanKeyVariants(item.rfid, tags.add);
    addScanKeyVariants(item.itemCode, tags.add);
    addScanKeyVariants(item.tid, tags.add);
    addScanKeyVariants(item.hex, tags.add);
    return tags.toList(growable: false);
  }

  /// One 24/32-bit chip so the reader filter cannot light a second LED.
  String? _oneChipEpc(SearchItem item) {
    String? chipOf(String raw) {
      final key = normalizeScanKey(raw);
      if (key.isEmpty) return null;
      if (isChipEpcHex(key)) return key;
      final stripped = stripScanKey00(key);
      if (isChipEpcHex(stripped)) return stripped;
      if (key.length >= 32 && isChipEpcHex(key.substring(0, 32))) {
        return key.substring(0, 32);
      }
      if (key.length >= 24 && isChipEpcHex(key.substring(0, 24))) {
        return key.substring(0, 24);
      }
      return null;
    }

    for (final raw in [item.rfid, item.epc, item.tid, item.hex]) {
      final chip = chipOf(raw);
      if (chip != null) return chip;
    }
    return null;
  }

  List<String> _collectSearchTags() {
    final tags = <String>{};
    void addItem(SearchItem item) {
      addScanKeyVariants(item.epc, tags.add);
      addScanKeyVariants(item.rfid, tags.add);
      addScanKeyVariants(item.itemCode, tags.add);
      addScanKeyVariants(item.tid, tags.add);
      addScanKeyVariants(item.hex, tags.add);
    }

    if (_searchQuery.trim().isEmpty && _tagIndexMap.isNotEmpty) {
      return _tagIndexMap.keys.toList(growable: false);
    }
    if (!_displayIndexValid) _rebuildDisplayIndices();
    for (var i = 0; i < _filteredCount; i++) {
      final item = _tryDisplayItemAt(i);
      if (item != null) addItem(item);
    }
    if (tags.isEmpty) {
      for (final item in _searchItems) {
        addItem(item);
      }
    }
    return tags.toList(growable: false);
  }

  /// LED rows on this inventory list only. A printed RFID (SJ0410) is a
  /// normal tag and must not take a blink slot. Rows that show "-" have no
  /// printed RFID; their chip is the LED tag (SP26–SP29).
  List<String> _collectInventoryLedEpcs() {
    final tags = <String>{};
    for (final item in _searchItems) {
      if (item.rfid.trim().isNotEmpty) continue;
      final chip = _oneChipEpc(item);
      if (chip == null) continue;
      tags.add(chip);
      if (tags.length >= 8) break;
    }
    return tags.toList(growable: false);
  }

  /// 24/32-bit LabelStock EPCs for Tag LED setFilter (demo checked tags).
  List<String> _collectSearchLedEpcs() {
    final tags = <String>{};
    void addChip(String raw) {
      final key = normalizeScanKey(raw);
      if (isChipEpcHex(key)) tags.add(key);
      final stripped = stripScanKey00(key);
      if (isChipEpcHex(stripped)) tags.add(stripped);
    }

    void addItem(SearchItem item) {
      addChip(item.epc);
      addChip(item.rfid);
      addChip(item.tid);
      addChip(item.hex);
    }

    if (_isLargeUnmatched && _searchQuery.trim().isEmpty) {
      return const <String>[];
    }
    if (!_displayIndexValid) _rebuildDisplayIndices();
    for (var i = 0; i < _filteredCount; i++) {
      final item = _tryDisplayItemAt(i);
      if (item != null) addItem(item);
    }
    if (tags.isEmpty) {
      for (final item in _searchItems) {
        addItem(item);
        if (tags.length >= 8) break;
      }
    }
    return tags.take(8).toList(growable: false);
  }

  void _rebuildDisplayIndices() {
    _ensureShuffledOrder();
    if (_isLargeUnmatched && _searchQuery.trim().isEmpty) {
      _filteredCount = _searchItems.length;
      _displayIndexValid = true;
      _queryScopeIndices.clear();
      return;
    }
    final query = _searchQuery.trim().toUpperCase().replaceAll(' ', '');
    final exact = <int>[];
    final rest = <int>[];
    for (final i in _displayOrder) {
      if (i < 0 || i >= _searchItems.length) continue;
      final item = _searchItems[i];
      if (query.isNotEmpty) {
        if (!item.normItemCode.contains(query) &&
            !item.normRfid.contains(query) &&
            !item.normEpc.contains(query) &&
            !item.normTid.contains(query) &&
            !item.normHex.contains(query)) {
          continue;
        }
        final isExact = item.normItemCode == query ||
            item.normRfid == query ||
            item.normEpc == query ||
            item.normTid == query ||
            item.normHex == query;
        if (isExact) {
          exact.add(i);
          continue;
        }
      }
      rest.add(i);
    }
    _visibleOrder
      ..clear()
      ..addAll(exact)
      ..addAll(rest);
    _filteredCount = _visibleOrder.length;
    _displayIndexValid = true;
    _queryScopeIndices.clear();
    if (_listKey == 'unmatchedItems' && query.isNotEmpty) {
      _queryScopeIndices.addAll(_visibleOrder);
    }
  }

  SearchItem? _itemAtDisplay(int index) {
    if (_shuffledGen != _orderGen || _displayOrder.length != _searchItems.length) {
      _ensureShuffledOrder();
      _mainDisplayDirty = true;
    }
    final pinned = _nearbyPinnedCount();
    if (pinned > 0) {
      _ensureMainDisplayOrder();
      if (index < 0 || index >= _mainDisplayOrder.length) return null;
      final i = _mainDisplayOrder[index];
      if (i < 0 || i >= _searchItems.length) return null;
      return _searchItems[i];
    }
    if (index < 0 || index >= _displayOrder.length) return null;
    final i = _displayOrder[index];
    if (i < 0 || i >= _searchItems.length) return null;
    return _searchItems[i];
  }

  SearchItem? _tryDisplayItemAt(int index) {
    if (index < 0 || index >= _visibleOrder.length) return null;
    final i = _visibleOrder[index];
    if (i < 0 || i >= _searchItems.length) return null;
    return _searchItems[i];
  }

  SearchItem _displayItemAt(int index) {
    final item = _tryDisplayItemAt(index);
    if (item != null) return item;
    if (_searchItems.isNotEmpty) return _searchItems.first;
    throw StateError('Search display is empty');
  }

  void _publishUnmatchedScreenKeys() {
    if (_listKey != 'unmatchedItems') return;
    final keys = <String>{};
    void addItem(SearchItem item) {
      for (final raw in [item.epc, item.rfid, item.itemCode, item.tid, item.hex]) {
        final key = _normScanKey(raw);
        if (key.isEmpty) continue;
        keys.add(key);
        final stripped = stripScanKey00(key);
        if (stripped.isNotEmpty && stripped != key) keys.add(stripped);
      }
    }

    if (_searchQuery.trim().isEmpty) {
      for (final item in _searchItems) {
        addItem(item);
      }
    } else {
      if (!_displayIndexValid) _rebuildDisplayIndices();
      for (var i = 0; i < _filteredCount; i++) {
        final item = _tryDisplayItemAt(i);
        if (item != null) addItem(item);
      }
    }
    UnmatchedSearchCatalog.instance.screenKeys = keys;
  }

  Future<void> _handOffToScanDisplay(
    VoidCallback? action, {
    bool forSave = false,
  }) async {
    if (_isHandingOff) return;
    _isHandingOff = true;
    if (mounted) setState(() {});
    if (_isScanning) await _stopSearchScan();
    if (!mounted) return;
    // Only Save publishes the search list. Menu and back must not
    // turn the next Inventory save into an Unmatched Search save.
    Set<String>? screenKeys;
    if (forSave) {
      _publishUnmatchedScreenKeys();
      screenKeys = UnmatchedSearchCatalog.instance.screenKeys;
    } else {
      UnmatchedSearchCatalog.instance.screenKeys = null;
    }
    Navigator.of(context).pop();
    if (screenKeys != null) {
      UnmatchedSearchCatalog.instance.screenKeys = screenKeys;
    }
    action?.call();
  }

  void _resetSearch() {
    unawaited(_stopSearchScan());
    _stopProximityDecay();
    _searchController.clear();
    _atMaxProximity.clear();
    _dirtyIndices.clear();
    _hotSet.clear();
    _hotIndices.clear();
    setState(() {
      _searchQuery = '';
      _isScanning = false;
      if (_listKey == 'normal') {
        _searchItems.clear();
        _tagIndexMap.clear();
      } else {
        for (var i = 0; i < _searchItems.length; i++) {
          final item = _searchItems[i];
          if (item.proximityPercent != 0 || item.rssi.isNotEmpty || item.positionLocked) {
            item.clearScan();
          }
        }
      }
      _invalidateDisplayOrder();
      _displayIndexValid = false;
    });
    _nearbyTick.value++;
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppFonts.poppins()),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isUnmatchedList = _listKey == 'unmatchedItems';
    final largeUnmatched = _isLargeUnmatched;
    final query = _searchQuery.trim();
    if (!largeUnmatched || query.isNotEmpty) {
      if (!_displayIndexValid) _rebuildDisplayIndices();
    }
    final statusFiltered = isUnmatchedList && _countFilter != _SearchCountFilter.all;
    final catalogCount = statusFiltered
        ? _statusListCount()
        : isUnmatchedList
            ? _unmatchedOpenCount()
            : _filteredCount;

    final catalog = UnmatchedSearchCatalog.instance;

    return PopScope(
      canPop: !(isUnmatchedList && _showMenu),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isUnmatchedList && _showMenu) {
          setState(() => _showMenu = false);
        }
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (isUnmatchedList && _showMenu) {
                  setState(() => _showMenu = false);
                  return;
                }
                Navigator.pop(context);
              },
            ),
            title: Text(
              isUnmatchedList ? s.searchUnmatched : s.searchAllItems,
              style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
            ),
            actions: [
              // White counter box showing selected power (1-30), same as Scan Display / Delivery Challan.
              PopupMenuButton<int>(
                tooltip: s.rfidPower,
                color: Colors.white,
                constraints: const BoxConstraints(maxHeight: 320, minWidth: 60),
                onSelected: (val) {
                  setState(() => _selectedPower = val);
                  _rfidService.setPower(val);
                  context.read<PrefService>().savePower(PrefService.keySearchCount, val);
                },
                itemBuilder: (context) => List.generate(30, (i) => i + 1)
                    .map((p) => PopupMenuItem<int>(
                          value: p,
                          height: 36,
                          child: Text('$p', style: AppFonts.poppins(fontSize: 14)),
                        ))
                    .toList(),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$_selectedPower',
                    style: AppFonts.poppins(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
        children: [
          // Dropdown for search type (Normal mode only)
          if (!isUnmatchedList)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, top: 12.0, bottom: 4.0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedSearchType,
                menuMaxHeight: kDropdownMenuMaxHeight,
                decoration: InputDecoration(
                  labelText: s.searchType,
                  labelStyle: AppFonts.poppins(fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'LabelStock', child: Text(s.labelStock, style: AppFonts.poppins(fontSize: 13))),
                  DropdownMenuItem(value: 'Order', child: Text(s.order, style: AppFonts.poppins(fontSize: 13))),
                  DropdownMenuItem(value: 'Box', child: Text(s.box, style: AppFonts.poppins(fontSize: 13))),
                ],
                onChanged: _isScanning
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSearchType = val;
                            _searchQuery = '';
                            _searchController.clear();
                            _searchItems.clear();
                          });
                        }
                      },
              ),
            ),

          // Search Field
          Padding(
            padding: EdgeInsets.only(
              left: 12.0,
              right: 12.0,
              top: isUnmatchedList ? 12.0 : 4.0,
              bottom: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              enabled: !_isScanning,
              decoration: InputDecoration(
                labelText: isUnmatchedList
                    ? s.enterRfidItemcode
                    : (_selectedSearchType == 'Order'
                        ? s.enterRfidCustomOrderId
                        : (_selectedSearchType == 'Box'
                            ? s.enterRfidBoxRfid
                            : s.enterRfidItemcode)),
                labelStyle: AppFonts.poppins(fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _onQueryChanged,
              style: AppFonts.poppins(fontSize: 13),
            ),
          ),

          if (isUnmatchedList) _buildUnmatchedCountBar(),

          // Table Header
          Container(
            color: const Color(0xFF3B363E),
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _selectedSearchType == 'Order' && !isUnmatchedList
                  ? [
                      _buildHeaderCell(s.headerSno, 1),
                      _buildHeaderCell(s.lblRfid, 2),
                      _buildHeaderCell(s.progress, 3),
                      _buildHeaderCell(s.percent, 1),
                    ]
                  : [
                      _buildHeaderCell(s.headerSno, 1),
                      _buildHeaderCell(s.lblRfid, 2),
                      _buildHeaderCell(s.itemcode, 2),
                      _buildHeaderCell(s.progress, 3),
                      _buildHeaderCell(s.percent, 1),
                    ],
            ),
          ),

          // Results list or empty placeholder
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (isUnmatchedList ? _searchItems.isEmpty : catalogCount == 0)
                    ? Center(
                        child: Text(
                          isUnmatchedList && _searchItems.isEmpty
                              ? s.noUnmatchedItemsToSearch
                              : s.typeRfidItemcodeToSearch,
                          style: AppFonts.poppins(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: catalogCount +
                            ((isUnmatchedList && !statusFiltered)
                                ? _nearbyPinnedCount()
                                : 0),
                        itemExtent: 34,
                        cacheExtent: 400,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: isUnmatchedList,
                        itemBuilder: (context, index) {
                          if (isUnmatchedList && !statusFiltered) {
                            final pinned = _nearbyPinnedCount();
                            if (index < pinned) {
                              final i = _hotIndices[index];
                              if (i < 0 || i >= _searchItems.length) {
                                return const SizedBox(height: 34);
                              }
                              return _buildSearchRow(_searchItems[i], index);
                            }
                            final item = _itemAtUnmatchedOpen(index - pinned);
                            if (item == null) return const SizedBox(height: 34);
                            return _buildSearchRow(item, index);
                          }
                          final item = statusFiltered
                              ? _itemAtStatus(index)
                              : _tryDisplayItemAt(index);
                          if (item == null) return const SizedBox(height: 34);
                          return _buildSearchRow(item, index);
                        },
                      ),
          ),

          // Bottom Navigation Bar
          if (isUnmatchedList)
            ScanBottomBarInventory(
              onSave: () {
                unawaited(_handOffToScanDisplay(catalog.onSave, forSave: true));
              },
              onList: () {
                setState(() => _showMenu = !_showMenu);
              },
              onScan: _toggleScanning,
              onEmail: () {
                catalog.onEmail?.call(context);
              },
              onReset: _resetSearch,
              isScanning: _isScanning,
              scanEnabled: !_isHandingOff,
            )
          else
            ScanBottomBar(
              onSave: () {},
              onList: () {
                Navigator.pushNamed(context, '/product_list');
              },
              onScan: _toggleScanning,
              onGscan: () {},
              onReset: _resetSearch,
              isScanning: _isScanning,
              saveEnabled: false,
              gscanEnabled: false,
            ),
        ],
      ),
          if (isUnmatchedList && _showMenu)
            ScanDisplayListMenuOverlay(
              matchedCount: catalog.matchedCountOf?.call() ?? 0,
              unmatchedCount: catalog.unmatchedCountOf?.call() ?? 0,
              unlabelledCount: catalog.unlabelledCountOf?.call() ?? 0,
              onDismiss: () => setState(() => _showMenu = false),
              onMatched: () {
                unawaited(_handOffToScanDisplay(() {
                  catalog.onSelectMenu?.call('MATCHED');
                }));
              },
              onUnmatched: () {
                unawaited(_handOffToScanDisplay(() {
                  catalog.onSelectMenu?.call('UNMATCHED');
                }));
              },
              onUnlabelled: () {
                unawaited(_handOffToScanDisplay(() {
                  catalog.onSelectMenu?.call('UNLABELLED');
                }));
              },
              onResumeScan: () {
                unawaited(_handOffToScanDisplay(catalog.onResumeScan));
              },
              onSearchUnmatched: () => setState(() => _showMenu = false),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildSearchRow(SearchItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: _selectedSearchType == 'Order' && _listKey != 'unmatchedItems'
            ? [
                _buildDataCell('${index + 1}', 1),
                _buildDataCell(item.rfid, 2),
                _buildProgressCell(item.proximityPercent, 3),
                _buildDataCell('${item.proximityPercent}%', 1),
              ]
            : [
                _buildDataCell('${index + 1}', 1),
                _buildDataCell(item.rfid, 2),
                _buildDataCell(item.itemCode, 2),
                _buildProgressCell(
                  item.proximityPercent,
                  3,
                  showAutoTick: _listKey != 'unmatchedItems',
                ),
                _buildDataCell('${item.proximityPercent}%', 1),
                if (_listKey == 'unmatchedItems') _buildManualMatchButton(item),
              ],
      ),
    );
  }

  int _statusListCount() {
    _ensureStatusOrder();
    return _statusOrder.length;
  }

  void _ensureStatusOrder() {
    if (_countFilter == _SearchCountFilter.all || !_statusOrderDirty) return;
    final wantMatched = _countFilter == _SearchCountFilter.matched;
    final next = <int>[];
    if (_isLargeUnmatched && _searchQuery.trim().isEmpty) {
      _ensureShuffledOrder();
      for (final i in _displayOrder) {
        if (i < 0 || i >= _searchItems.length) continue;
        if (_searchItems[i].manuallyMatched == wantMatched) next.add(i);
      }
    } else {
      if (!_displayIndexValid) _rebuildDisplayIndices();
      for (final i in _visibleOrder) {
        if (i < 0 || i >= _searchItems.length) continue;
        if (_searchItems[i].manuallyMatched == wantMatched) next.add(i);
      }
    }
    _statusOrder = next;
    _statusOrderDirty = false;
  }

  SearchItem? _itemAtStatus(int index) {
    _ensureStatusOrder();
    if (index < 0 || index >= _statusOrder.length) return null;
    final i = _statusOrder[index];
    if (i < 0 || i >= _searchItems.length) return null;
    return _searchItems[i];
  }

  void _selectCountFilter(_SearchCountFilter filter) {
    if (_countFilter == filter) return;
    setState(() {
      _countFilter = filter;
      _statusOrderDirty = true;
    });
  }

  Widget _buildUnmatchedCountBar() {
    final total = _searchItems.length;
    final matched = _manualMatchedCount.clamp(0, total);
    final unmatched = total - matched;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          _countChip('Search Count', total, _SearchCountFilter.all),
          const SizedBox(width: 6),
          _countChip('Match Count', matched, _SearchCountFilter.matched),
          const SizedBox(width: 6),
          _countChip('Unmatch Count', unmatched, _SearchCountFilter.unmatched),
        ],
      ),
    );
  }

  Widget _countChip(String label, int count, _SearchCountFilter filter) {
    final selected = _countFilter == filter;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFFE8F5E9) : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _selectCountFilter(filter),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? const Color(0xFF2E7D32) : const Color(0xFFE0E0E0),
              ),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.poppins(fontSize: 9, color: Colors.black54),
                ),
                Text(
                  '$count',
                  style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSearchedItem(SearchItem item) {
    if (!item.manuallyMatched && item.proximityPercent <= 0) return;
    if (item.manuallyMatched) {
      item.manuallyMatched = false;
      if (_manualMatchedCount > 0) _manualMatchedCount--;
    } else {
      item.manuallyMatched = true;
      _manualMatchedCount++;
    }
    _statusOrderDirty = true;
    setState(() {});
  }

  Widget _buildManualMatchButton(SearchItem item) {
    final matched = item.manuallyMatched;
    final canMark = matched || item.proximityPercent > 0;
    return SizedBox(
      width: 28,
      height: 22,
      child: Material(
        color: matched
            ? Colors.transparent
            : (canMark ? const Color(0xFFBDBDBD) : const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: canMark ? () => _toggleSearchedItem(item) : null,
          child: matched
              ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDataCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text.isNotEmpty ? text : '-',
        style: AppFonts.poppins(fontSize: 11, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildProgressCell(int proximity, int flex, {bool showAutoTick = true}) {
    final value = proximity / 100.0;
    final isMatched = showAutoTick && proximity >= 80;
    return Expanded(
      flex: flex,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(getColorByPercentage(proximity)),
                ),
              ),
            ),
          ),
          if (isMatched) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 16,
            ),
          ],
        ],
      ),
    );
  }
}

enum _SearchCountFilter { all, matched, unmatched }
