import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../viewmodels/daily_rate_view_model.dart';

// Brand gradient (purple -> red) used across the app.
const _brandGradient = LinearGradient(
  colors: [Color(0xFF5231A7), Color(0xFFD32940)],
);
const _buttonGradient = LinearGradient(
  colors: [Color(0xFFD32940), Color(0xFF5231A7)],
);

class TodaysRateScreen extends StatefulWidget {
  const TodaysRateScreen({super.key});

  @override
  State<TodaysRateScreen> createState() => _TodaysRateScreenState();
}

class _TodaysRateScreenState extends State<TodaysRateScreen> {
  final List<TextEditingController> _controllers = [];
  bool _controllersBuilt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DailyRateViewModel>().loadRates();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _buildControllers(DailyRateViewModel vm) {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers
      ..clear()
      ..addAll(vm.rates.map((r) => TextEditingController(text: r.rate)));
    _controllersBuilt = true;
  }

  // Push recalculated sibling rates into their controllers, leaving the field
  // the user is actively editing untouched (so the cursor doesn't jump).
  void _syncControllersExcept(DailyRateViewModel vm, int activeIndex) {
    for (int j = 0; j < vm.rates.length && j < _controllers.length; j++) {
      if (j == activeIndex) continue;
      final newText = vm.rates[j].rate;
      if (_controllers[j].text != newText) {
        _controllers[j].value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  Future<void> _onUpdate(DailyRateViewModel vm) async {
    final s = context.sRead;
    final ok = await vm.submitUpdate();
    if (!mounted) return;
    final msg = vm.updateMessage ?? (ok ? s.ratesUpdatedSuccessfully : s.failedToUpdateRates);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    vm.resetUpdateState();
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DailyRateViewModel>();

    // (Re)build controllers when the row set first arrives or its size changes.
    if (vm.rates.isNotEmpty &&
        (!_controllersBuilt || _controllers.length != vm.rates.length)) {
      _buildControllers(vm);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _buildBody(vm),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: _brandGradient)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        context.s.labelTodayRate,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBody(DailyRateViewModel vm) {
    if (vm.isLoading && vm.rates.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)));
    }

    if (vm.rates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            vm.errorMessage ?? context.s.noRatesFound,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildHeaderRow(),
          Divider(thickness: 1, height: 1, color: Colors.grey.withValues(alpha: 0.4)),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: vm.rates.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
              itemBuilder: (context, index) => _buildDataRow(vm, index),
            ),
          ),
          const SizedBox(height: 12),
          _buildButtons(vm),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    final s = context.s;
    Widget cell(String text, int flex) => Expanded(
          flex: flex,
          child: Text(
            text,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          cell(s.fieldCategory, 3),
          cell(s.fieldPurity, 2),
          cell(s.todayRatePerGm, 3),
        ],
      ),
    );
  }

  Widget _buildDataRow(DailyRateViewModel vm, int index) {
    final row = vm.rates[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.categoryName,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.purityName,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 3,
            child: _buildRateField(vm, index),
          ),
        ],
      ),
    );
  }

  Widget _buildRateField(DailyRateViewModel vm, int index) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _controllers.length > index ? _controllers[index] : null,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          _SingleDecimalFormatter(),
        ],
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.black),
        cursorColor: Colors.black,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFD3D3D3), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.grey, width: 1),
          ),
        ),
        onChanged: (value) {
          vm.updateRateAt(index, value);
          _syncControllersExcept(vm, index);
        },
      ),
    );
  }

  Widget _buildButtons(DailyRateViewModel vm) {
    final s = context.s;
    return Row(
      children: [
        Expanded(
          child: _GradientButton(
            text: s.cancel,
            icon: Icons.close,
            onTap: () => Navigator.pop(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GradientButton(
            text: s.update,
            icon: Icons.check_circle,
            loading: vm.updateStatus == RateUpdateStatus.loading,
            onTap: vm.updateStatus == RateUpdateStatus.loading ? null : () => _onUpdate(vm),
          ),
        ),
      ],
    );
  }
}

/// Allows at most one decimal point in the input.
class _SingleDecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.split('.').length > 2) {
      return oldValue;
    }
    return newValue;
  }
}

class _GradientButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  const _GradientButton({
    required this.text,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            gradient: _buttonGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
