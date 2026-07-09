import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../../models/sample_out.dart';
import '../../services/pref_service.dart';
import '../../services/rfid_service.dart';
import '../../viewmodels/sample_in_view_model.dart';
import 'widgets/add_customer_dialog.dart';
import 'widgets/challan_details_dialog.dart';
import 'widgets/sample_in_table.dart';
import 'widgets/sample_out_fields_dialog.dart';
import 'widgets/sample_print_pdf.dart';
import '../utils/tag_scan_batcher.dart';
import 'widgets/scan_bottom_bar.dart';

class SampleInScreen extends StatefulWidget {
  const SampleInScreen({super.key});

  @override
  State<SampleInScreen> createState() => _SampleInScreenState();
}

class _SampleInScreenState extends State<SampleInScreen> {
  final RfidService _rfidService = RfidService();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _customerSearchCtrl = TextEditingController();
  final TextEditingController _sampleOutNoCtrl = TextEditingController();
  final FocusNode _sampleOutFocus = FocusNode();
  StreamSubscription? _rfidSubscription;
  StreamSubscription? _triggerSubscription;
  bool _showCustomerSuggestions = false;
  bool _showSampleOutSuggestions = false;
  int _power = 30;
  bool _isSingleScan = false;
  Map<String, dynamic>? _pendingMatchIssue;
  Map<String, dynamic>? _pendingRemoveIssue;
  late final TagScanBatcher _tagBatcher;

  @override
  void initState() {
    super.initState();
    _tagBatcher = TagScanBatcher(
      onFlush: (tags) {
        if (!mounted || !_rfidService.isScanning) return;
        context.read<SampleInViewModel>().processScannedTags(tags);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<SampleInViewModel>();
      if (vm.customers.isEmpty) await vm.loadMasterData();
      if (vm.selectedChallan != null) {
        await vm.loadIssueBulkItems();
        _sampleOutNoCtrl.text = vm.selectedChallan!.sampleOutNo;
      }
      if (vm.selectedCustomer != null) {
        _customerSearchCtrl.text =
            '${vm.selectedCustomer!.firstName ?? ''} ${vm.selectedCustomer!.lastName ?? ''}'.trim();
      }
    });

    _rfidSubscription = _rfidService.tagsStream.listen((epc) {
      if (!_rfidService.isScanning) return;
      _tagBatcher.add(epc);
      if (_isSingleScan) {
        _tagBatcher.flushNow();
        _isSingleScan = false;
        _toggleGscan(context.read<SampleInViewModel>());
      }
    });

    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (mounted) {
        _isSingleScan = false;
        _toggleGscan(context.read<SampleInViewModel>());
      }
    });
  }

  @override
  void dispose() {
    _tagBatcher.dispose();
    _rfidSubscription?.cancel();
    _triggerSubscription?.cancel();
    _rfidService.stopScanning();
    _customerSearchCtrl.dispose();
    _sampleOutNoCtrl.dispose();
    _sampleOutFocus.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleGscan(SampleInViewModel vm) async {
    if (_rfidService.isScanning) {
      await _rfidService.stopScanning();
      if (mounted) setState(() {});
      return;
    }

    if (vm.issueItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.sRead.selectSampleOutNoFirst)),
        );
      }
      return;
    }

    await vm.loadIssueBulkItems();
    if (!mounted) return;

    final scopeTags = vm.scanScopeTags;
    if (scopeTags.isNotEmpty) {
      await _rfidService.setMatchEpcs(scopeTags);
    }

    final started = await _rfidService.startScanning(
      power: _power,
      simulatedScopeTags: scopeTags,
    );
    if (mounted) setState(() {});
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.sRead.failedToStartRfidScanner)));
    }
  }

  Widget _gradientBorder({required Widget child, double radius = 10}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius - 1)),
        child: child,
      ),
    );
  }

  void _showFieldsDialog(SampleInViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => SampleOutFieldsDialog(
        initialDate: vm.selectedDate,
        initialReturnDate: vm.returnDate,
        initialDescription: vm.description,
        onConfirm: (fields) {
          vm.setSampleInFields(
            date: fields['date'] ?? '',
            returnDate: fields['returnDate'] ?? '',
            description: fields['description'] ?? '',
          );
        },
      ),
    );
  }

  void _showAddCustomerDialog() {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) => AddCustomerDialog(
        title: s.customerProfile,
        onSave: (req) async {
          final vm = context.read<SampleInViewModel>();
          final cc = context.read<PrefService>().getEmployee()?.clientCode ?? '';
          final payload = {
            'FirstName': req['FirstName'],
            'MiddleName': '',
            'LastName': req['LastName'],
            'Email': req['Email'],
            'CustomerLoginId': req['Email'],
            'Password': '',
            'Gender': '',
            'CustomerSlabId': 0,
            'CreditPeriodId': 0,
            'RateOfInterestId': 0,
            'Mobile': req['Mobile'],
            'OnlineStatus': 'Active',
            'DateOfBirth': '',
            'AdvanceAmount': '0',
            'BalanceAmount': '0',
            'CurrAddStreet': req['PerAddStreet'],
            'Area': '',
            'PerAddTown': '',
            'City': req['City'],
            'CurrAddState': req['CurrAddState'],
            'CurrAddPincode': '',
            'PerAddStreet': '',
            'PerAddState': '',
            'PerAddPincode': '',
            'Country': req['Country'],
            'PerAddCountry': '',
            'AadharNo': '',
            'Discount': '0',
            'CreditPeriod': '0',
            'PanNo': req['PanNo'],
            'FineGold': '0',
            'FineSilver': '0',
            'GstNo': req['GstNo'],
            'ClientCode': cc,
            'VendorId': 0,
            'Remark': '',
            'AddToVendor': false,
            'Id': 0,
          };
          final success = await vm.addCustomerProfile(payload);
          if (!mounted) return;
          if (success) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.customerAddedSuccessfully)));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? s.errorAddingCustomer)));
          }
        },
      ),
    );
  }

  void _showItemEditDialog(int index, SampleInViewModel vm) {
    final issue = vm.issueItems[index];
    showDialog(
      context: context,
      builder: (context) => ChallanDetailsDialog(
        item: vm.issueToDetails(issue),
        branches: const [],
        dailyRates: vm.dailyRates,
        onSave: (updated) => vm.updateIssueItem(index, updated),
      ),
    );
  }

  void _onRowTap(SampleInViewModel vm, Map<String, dynamic> issue) {
    if (vm.isIssueMatched(issue)) {
      _pendingRemoveIssue = issue;
      _showRemoveDialog(vm);
    } else {
      _pendingMatchIssue = issue;
      _showMatchDialog(vm);
    }
  }

  void _showMatchDialog(SampleInViewModel vm) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF5231A7)),
            const SizedBox(width: 8),
            Text(s.confirmMatch, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(s.confirmAddMatched, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(onPressed: () { setState(() => _pendingMatchIssue = null); Navigator.pop(ctx); }, child: Text(s.no)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5231A7)),
            onPressed: () {
              if (_pendingMatchIssue != null) {
                vm.manualMatchIssue(_pendingMatchIssue!);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.itemAddedInMatchedList)));
              }
              _pendingMatchIssue = null;
              Navigator.pop(ctx);
            },
            child: Text(s.yes, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(SampleInViewModel vm) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.red),
            const SizedBox(width: 8),
            Text(s.removeMatch, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(s.confirmRemoveMatched, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(onPressed: () { setState(() => _pendingRemoveIssue = null); Navigator.pop(ctx); }, child: Text(s.no)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (_pendingRemoveIssue != null) {
                vm.manualRemoveIssue(_pendingRemoveIssue!);
              }
              _pendingRemoveIssue = null;
              Navigator.pop(ctx);
            },
            child: Text(s.yes, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInput(SampleInViewModel vm) {
    final s = context.s;
    final query = _customerSearchCtrl.text.toLowerCase().trim();
    final visible = vm.customers.where((c) {
      final name = '${c.firstName ?? ''} ${c.lastName ?? ''}'.toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Column(
        children: [
          _gradientBorder(
            child: SizedBox(
              height: 35,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _customerSearchCtrl,
                        focusNode: _focusNode,
                        style: GoogleFonts.poppins(fontSize: 13),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: s.enterCustomerName,
                          hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                        ),
                        onChanged: (_) => setState(() => _showCustomerSuggestions = true),
                      ),
                    ),
                    if (_customerSearchCtrl.text.isEmpty)
                      InkWell(onTap: _showAddCustomerDialog, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add, color: Colors.grey, size: 18)))
                    else
                      InkWell(
                        onTap: () {
                          _customerSearchCtrl.clear();
                          vm.setSelectedCustomer(null);
                          _sampleOutNoCtrl.clear();
                          setState(() => _showCustomerSuggestions = false);
                        },
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.clear, color: Colors.grey, size: 18)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_showCustomerSuggestions && visible.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final c = visible[i];
                  final name = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
                  return ListTile(
                    title: Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(s.mobileLabel(c.mobile ?? '-'), style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      _customerSearchCtrl.text = name;
                      vm.setSelectedCustomer(c);
                      _sampleOutNoCtrl.clear();
                      setState(() => _showCustomerSuggestions = false);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSampleOutNoRow(SampleInViewModel vm) {
    final s = context.s;
    final query = _sampleOutNoCtrl.text.trim().toLowerCase();
    final suggestions = query.isEmpty
        ? <SampleOutModel>[]
        : vm.customerWiseSampleOuts
            .where((c) => c.sampleOutNo.toLowerCase().contains(query))
            .take(50)
            .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 11,
                child: _gradientBorder(
                  child: SizedBox(
                    height: 35,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _sampleOutNoCtrl,
                              focusNode: _sampleOutFocus,
                              enabled: vm.selectedCustomer != null,
                              style: GoogleFonts.poppins(fontSize: 13),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: vm.selectedCustomer == null ? s.selectCustomerFirst : s.enterSampleOutNo,
                                hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                              ),
                              onChanged: (v) => setState(() => _showSampleOutSuggestions = v.isNotEmpty),
                            ),
                          ),
                          if (_sampleOutNoCtrl.text.isNotEmpty)
                            InkWell(
                              onTap: () {
                                _sampleOutNoCtrl.clear();
                                vm.clearSelectedChallan();
                                setState(() => _showSampleOutSuggestions = false);
                              },
                              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.clear, color: Colors.grey, size: 18)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 8,
                child: GestureDetector(
                  onTap: () => _showFieldsDialog(vm),
                  child: _gradientBorder(
                    radius: 8,
                    child: SizedBox(
                      height: 35,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.sampleIn, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
                          const SizedBox(width: 4),
                          const Icon(Icons.tune, size: 20, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showSampleOutSuggestions && suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 3))],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (context, i) {
                  final challan = suggestions[i];
                  return InkWell(
                    onTap: () {
                      _sampleOutNoCtrl.text = challan.sampleOutNo;
                      vm.selectSampleOut(challan);
                      setState(() => _showSampleOutSuggestions = false);
                      _sampleOutFocus.unfocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        s.sampleOutItemsCount(challan.sampleOutNo, challan.issueItems.length),
                        style: GoogleFonts.poppins(fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SampleInViewModel>();
    final s = context.s;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)])),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            vm.clearSampleIn();
            Navigator.pop(context);
          },
        ),
        title: Text(s.sampleIn, style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          PopupMenuButton<int>(
            color: Colors.white,
            onSelected: (val) {
              setState(() => _power = val);
              _rfidService.setPower(val);
            },
            itemBuilder: (context) => List.generate(30, (i) => i + 1)
                .map((p) => PopupMenuItem(value: p, child: Text(s.powerLabel(p), style: GoogleFonts.poppins(fontSize: 14))))
                .toList(),
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text('$_power', style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            _buildCustomerInput(vm),
            const SizedBox(height: 4),
            _buildSampleOutNoRow(vm),
            const SizedBox(height: 4),
            Expanded(
              child: SampleInTable(
                issueItems: vm.issueItems,
                scannedCodes: vm.scannedCodes,
                isReturnMode: vm.isReturnMode,
                selectedReturnCodes: vm.selectedReturnCodes,
                isMatched: vm.isIssueMatched,
                onReturnModeChange: vm.setReturnMode,
                onReturnToggle: vm.toggleReturnSelection,
                onRowTap: (issue) => _onRowTap(vm, issue),
                onRowLongPress: (issue, index) => _showItemEditDialog(index, vm),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ScanBottomBar(
        isScanning: _rfidService.isScanning && _isSingleScan,
        isBulkScanning: _rfidService.isScanning && !_isSingleScan,
        isEditMode: false,
        onSave: () async {
          final s = context.sRead;
          final success = await vm.submitSampleIn();
          if (!mounted) return;
          if (success) {
            final printData = vm.buildSampleInPrintData(apiResponse: vm.lastSaveResponse);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.sampleInSavedSuccessfully)));
            await printSamplePrintPdf(context: context, data: printData);
            if (!mounted) return;
            vm.clearSampleIn();
            _customerSearchCtrl.clear();
            _sampleOutNoCtrl.clear();
            Navigator.pop(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? s.failedToSaveSampleIn)));
          }
        },
        onList: () {
          vm.clearSampleIn();
          Navigator.pushReplacementNamed(context, '/sample_in_list');
        },
        onScan: () async {
          if (_rfidService.isScanning && !_isSingleScan) {
            await _rfidService.stopScanning();
            if (mounted) setState(() {});
            _isSingleScan = true;
            _toggleGscan(vm);
            return;
          }
          if (_rfidService.isScanning) {
            _isSingleScan = false;
            _toggleGscan(vm);
          } else {
            _isSingleScan = true;
            _toggleGscan(vm);
          }
        },
        onGscan: () async {
          if (_rfidService.isScanning && _isSingleScan) {
            await _rfidService.stopScanning();
            if (mounted) setState(() {});
            _isSingleScan = false;
            _toggleGscan(vm);
            return;
          }
          _isSingleScan = false;
          _toggleGscan(vm);
        },
        onReset: () {
          vm.clearSampleIn();
          _customerSearchCtrl.clear();
          _sampleOutNoCtrl.clear();
        },
      ),
    );
  }
}
