import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/location_item.dart';
import '../services/locale_service.dart';
import '../services/maps_helper.dart';
import '../viewmodels/settings_view_model.dart';
import 'widgets/product_form_widgets.dart';

class LocationListScreen extends StatefulWidget {
  const LocationListScreen({super.key});

  @override
  State<LocationListScreen> createState() => _LocationListScreenState();
}

class _LocationListScreenState extends State<LocationListScreen> {
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsViewModel>().fetchLocationsFromDb();
    });
  }

  String _formatCreatedOn(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final normalized = raw.length >= 19 ? raw.substring(0, 19) : raw;
      final dt = DateTime.parse(normalized);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  bool _isSameDay(String? createdOn, DateTime selected) {
    if (createdOn == null) return false;
    try {
      final normalized = createdOn.length >= 19 ? createdOn.substring(0, 19) : createdOn;
      final dt = DateTime.parse(normalized);
      return DateFormat('dd/MM/yyyy').format(dt) == DateFormat('dd/MM/yyyy').format(selected);
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _openRoute(List<LocationItem> all) async {
    if (_selectedDate == null) return;
    final dayLocations = all.where((item) => _isSameDay(item.createdOn, _selectedDate!)).toList()
      ..sort((a, b) => (a.createdOn ?? '').compareTo(b.createdOn ?? ''));
    if (dayLocations.length < 2) return;
    await MapsHelper.openDayRoute(dayLocations);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleService>().strings;
    final vm = context.watch<SettingsViewModel>();

    return Directionality(
      textDirection: context.watch<LocaleService>().textDirection,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: productGradientAppBar(context: context, title: s.locationList),
        body: vm.loadingLocations
            ? const Center(child: CircularProgressIndicator())
            : vm.locations.isEmpty
                ? Center(child: Text(s.noLocationsFound, style: GoogleFonts.poppins(fontSize: 14)))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _pickDate,
                                child: Text(
                                  _selectedDate == null ? s.selectDate : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                                  style: GoogleFonts.poppins(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: s.route,
                              onPressed: _selectedDate == null ? null : () => _openRoute(vm.locations),
                              icon: const Icon(Icons.navigation, color: Color(0xFF5231A7)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        color: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(flex: 1, child: Text(s.headerSr, style: _headerStyle())),
                            Expanded(flex: 2, child: Text(s.date, style: _headerStyle())),
                            Expanded(flex: 2, child: Text(s.userId, style: _headerStyle(), textAlign: TextAlign.center)),
                            Expanded(flex: 3, child: Text(s.address, style: _headerStyle())),
                            const SizedBox(width: 36),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Colors.grey),
                      Expanded(
                        child: ListView.separated(
                          itemCount: vm.locations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = vm.locations[index];
                            final dateLabel = _formatCreatedOn(item.createdOn);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(flex: 1, child: Text('${index + 1}', style: _cellStyle())),
                                  Expanded(flex: 2, child: Text(dateLabel, style: _cellStyle())),
                                  Expanded(
                                    flex: 2,
                                    child: Text('${item.userId ?? '-'}', style: _cellStyle(), textAlign: TextAlign.center),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(item.address ?? '-', style: _cellStyle(), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    icon: const Icon(Icons.location_on, color: Colors.red, size: 22),
                                    onPressed: () => MapsHelper.openSinglePoint(
                                      latitude: item.latitude,
                                      longitude: item.longitude,
                                      label: '$dateLabel - ${item.address ?? ''}',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  TextStyle _headerStyle() => GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, height: 1.1);
  TextStyle _cellStyle() => GoogleFonts.poppins(fontSize: 11, height: 1.15, color: Colors.black87);
}
