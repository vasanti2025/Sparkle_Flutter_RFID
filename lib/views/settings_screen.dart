import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../l10n/l10n_extension.dart';
import '../services/locale_service.dart';
import '../services/pref_service.dart';
import '../utils/bluetooth_permission_util.dart';
import '../viewmodels/settings_view_model.dart';
import 'widgets/product_form_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final s = locale.strings;
    final vm = context.watch<SettingsViewModel>();
    final pref = vm.pref;
    final employee = pref.getEmployee();

    return Directionality(
      textDirection: locale.textDirection,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: productGradientAppBar(context: context, title: s.settings),
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              _PowerRow(title: s.product, prefKey: PrefService.keyProductCount, vm: vm),
              _PowerRow(title: s.inventory, prefKey: PrefService.keyInventoryCount, vm: vm),
              _PowerRow(title: s.search, prefKey: PrefService.keySearchCount, vm: vm),
              _PowerRow(title: s.order, prefKey: PrefService.keyOrderCount, vm: vm),
              _PowerRow(title: s.stockTransfer, prefKey: PrefService.keyStockTransferCount, vm: vm),
              _ActionRow(
                title: s.language,
                trailingText: s.languageLabel(locale.languageCode),
                onTap: () => _showLanguageDialog(context, locale),
              ),
              _LocationRow(vm: vm, strings: s),
              _ActionRow(
                title: s.account,
                trailingText: s.usernamePassword,
                onTap: () => _showAccountDialog(context, pref, s),
              ),
              _ActionRow(
                title: s.userPermission,
                trailingText: s.managePermission,
                onTap: () => _showInfoDialog(context, s.userPermission, s.permissionsFromServer, s),
              ),
              _ActionRow(
                title: s.email,
                trailingText: employee?.empEmail ?? s.defaultLoginEmail,
                onTap: () {},
              ),
              _ActionRow(
                title: s.backup,
                trailingText: s.dataBackup,
                onTap: () => _showBackupDialog(context, vm, s),
              ),
              _ActionRow(
                title: s.autoSync,
                trailingText: s.enableAutomaticSync,
                onTap: () => _showAutoSyncDialog(context, vm, pref, s),
              ),
              _ActionRow(
                title: s.notifications,
                trailingText: s.notificationSettings,
                onTap: () => _showNotificationsDialog(context, vm, pref, s),
              ),
              _ActionRow(
                title: s.branches,
                trailingText: s.branchManagement,
                onTap: () => _showBranchesDialog(context, pref, s),
              ),
              _ActionRow(
                title: s.customApi,
                trailingText: s.configureApiUrl,
                onTap: () => _showCustomApiDialog(context, vm, pref, s),
              ),
              _ActionRow(
                title: s.sheetUrl,
                trailingText: s.setGoogleSheetUrl,
                onTap: () => _showSheetUrlDialog(context, vm, pref, s),
              ),
              _ActionRow(
                title: s.stockTransferUrl,
                trailingText: s.stockTransferApiUrl,
                onTap: () => _showStockTransferUrlDialog(context, vm, pref, s),
              ),
              _ActionRow(
                title: s.privacyPolicy,
                trailingText: s.viewPrivacyPolicy,
                onTap: () => Navigator.pushNamed(context, '/privacy_policy'),
              ),
              _ActionRow(
                title: s.faceData,
                trailingText: s.addFaceLoginData,
                onTap: () => Navigator.pushNamed(context, '/add_face'),
              ),
              _WifiModeRow(vm: vm, s: s),
              _TrayModeRow(vm: vm, s: s),
              _ReusableTagsRow(vm: vm, s: s),
              _ActionRow(
                title: s.clearData,
                trailingText: s.clearLocalData,
                onTap: () => _showClearDataDialog(context, vm, s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showLanguageDialog(BuildContext context, LocaleService locale) {
    final s = locale.strings;
    var selected = locale.languageCode;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.selectLanguage, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppStrings.supported.map((code) {
              return RadioListTile<String>(
                title: Text(s.languageLabel(code), style: GoogleFonts.poppins()),
                value: code,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v ?? selected),
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            TextButton(
              onPressed: () async {
                await locale.setLanguage(selected);
                if (context.mounted) Navigator.pop(ctx);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  static void _showAccountDialog(BuildContext context, PrefService pref, AppStrings s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.account, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.usernameLabel}: ${pref.getSavedUsername()}', style: GoogleFonts.poppins()),
            const SizedBox(height: 8),
            Text('${s.password}: ${pref.getSavedPassword().isEmpty ? '—' : '••••••••'}', style: GoogleFonts.poppins()),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
      ),
    );
  }

  static void _showInfoDialog(BuildContext context, String title, String message, AppStrings s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(message, style: GoogleFonts.poppins()),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
      ),
    );
  }

  static void _showBackupDialog(BuildContext context, SettingsViewModel vm, AppStrings s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.backupOptions, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(s.backupChoose, style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final file = await vm.saveBackupToDevice();
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.savedTo}: ${file.path}')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.backupFailed}: $e')));
                }
              }
            },
            child: Text(s.saveToDevice),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showBackupEmailDialog(context, vm, s);
            },
            child: Text(s.sendViaEmail),
          ),
          TextButton(
            onPressed: () async {
              try {
                await vm.restoreBackup();
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.restoreComplete)));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.backupFailed}: $e')));
                }
              }
            },
            child: Text(s.restoreBackup),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
        ],
      ),
    );
  }

  static void _showBackupEmailDialog(BuildContext context, SettingsViewModel vm, AppStrings s) {
    final ctrl = TextEditingController(text: vm.pref.getBackupEmail());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.enterEmailAddress, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: s.email, border: const OutlineInputBorder()),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              try {
                await vm.sendBackupEmail(email);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.sendViaEmail}: $email')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.backupFailed}: $e')));
                }
              }
            },
            child: Text(s.send),
          ),
        ],
      ),
    );
  }

  static void _showAutoSyncDialog(BuildContext context, SettingsViewModel vm, PrefService pref, AppStrings s) {
    var enabled = pref.isAutosyncEnabled();
    var interval = pref.getAutosyncIntervalMin();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.autoSyncSettings, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(s.autoSync, style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                  Switch(
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                ],
              ),
              if (enabled) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text(s.syncInterval, style: GoogleFonts.poppins())),
                    DropdownButton<int>(
                      value: interval,
                      items: [
                        DropdownMenuItem(value: 15, child: Text(s.min15)),
                        DropdownMenuItem(value: 30, child: Text(s.min30)),
                        DropdownMenuItem(value: 60, child: Text(s.hour1)),
                        DropdownMenuItem(value: 1440, child: Text(s.hour24)),
                      ],
                      onChanged: (v) => setState(() => interval = v ?? 15),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            TextButton(
              onPressed: () async {
                await vm.setAutosync(enabled, interval);
                if (context.mounted) Navigator.pop(ctx);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  static void _showNotificationsDialog(BuildContext context, SettingsViewModel vm, PrefService pref, AppStrings s) {
    var enabled = pref.areNotificationsEnabled();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.notifications, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SwitchListTile(
            title: Text(s.enableNotifications, style: GoogleFonts.poppins()),
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            TextButton(
              onPressed: () async {
                await vm.setNotificationsEnabled(enabled);
                if (context.mounted) Navigator.pop(ctx);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  static void _showBranchesDialog(BuildContext context, PrefService pref, AppStrings s) {
    final ids = pref.getBranchIds();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.branches, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('${s.selectedBranchIds}: ${ids.join(', ')}', style: GoogleFonts.poppins()),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
      ),
    );
  }

  static void _showCustomApiDialog(BuildContext context, SettingsViewModel vm, PrefService pref, AppStrings s) {
    final ctrl = TextEditingController(text: pref.getCustomApi() ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.customApi, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: s.customApiUrlHint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () async {
              await vm.saveCustomApi(ctrl.text.trim());
              if (context.mounted) Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  static void _showSheetUrlDialog(BuildContext context, SettingsViewModel vm, PrefService pref, AppStrings s) {
    final ctrl = TextEditingController(text: pref.getSheetUrl());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.sheetUrl, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: s.setGoogleSheetUrl, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () async {
              await vm.saveSheetUrl(ctrl.text.trim());
              if (context.mounted) Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  static void _showStockTransferUrlDialog(BuildContext context, SettingsViewModel vm, PrefService pref, AppStrings s) {
    final ctrl = TextEditingController(text: pref.getStockTransferUrl());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.stockTransferUrl, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: s.stockTransferApiUrl, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () async {
              await vm.saveStockTransferUrl(ctrl.text.trim());
              if (context.mounted) Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  static void _showClearDataDialog(BuildContext context, SettingsViewModel vm, AppStrings s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmClearData, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(s.clearDataMessage, style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showPasswordDialog(context, vm, s);
            },
            child: Text(s.continueLabel),
          ),
        ],
      ),
    );
  }

  static void _showPasswordDialog(BuildContext context, SettingsViewModel vm, AppStrings s) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.verifyPassword, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: InputDecoration(hintText: s.password, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () async {
              final ok = await vm.clearAllData(ctrl.text);
              if (!context.mounted) return;
              Navigator.pop(ctx);
              if (ok) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.incorrectPassword)));
              }
            },
            child: Text(s.clearBtn),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final SettingsViewModel vm;
  final AppStrings strings;

  const _LocationRow({required this.vm, required this.strings});

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      title: strings.location,
      trailingText: vm.locationSyncEnabled ? strings.enabled : strings.disabled,
      trailing: Switch(
        value: vm.locationSyncEnabled,
        onChanged: (value) async {
          final ok = await vm.setLocationSyncEnabled(value);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.failedToGetLocation)),
            );
          }
        },
      ),
      onTap: () async {
        await vm.refreshLocationsFromServer();
        if (context.mounted) {
          Navigator.pushNamed(context, '/location_list');
        }
      },
    );
  }
}

class _PowerRow extends StatelessWidget {
  final String title;
  final String prefKey;
  final SettingsViewModel vm;

  const _PowerRow({required this.title, required this.prefKey, required this.vm});

  @override
  Widget build(BuildContext context) {
    final value = vm.getPower(prefKey);
    return _SettingsTile(
      title: title,
      trailing: _PowerCounter(
        value: value,
        onSelected: (v) => vm.savePower(prefKey, v),
      ),
    );
  }
}

class _PowerCounter extends StatelessWidget {
  final int value;
  final ValueChanged<int> onSelected;

  const _PowerCounter({required this.value, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: context.s.rfidPower,
      offset: const Offset(0, 36),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      itemBuilder: (_) => List.generate(
        30,
        (i) => PopupMenuItem(value: i + 1, height: 32, child: Text('${i + 1}', style: _SettingsStyles.menuItem)),
      ),
      onSelected: onSelected,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD0D0D0), width: 0.5),
        ),
        child: Text('$value', style: _SettingsStyles.counter),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String title;
  final String trailingText;
  final VoidCallback onTap;

  const _ActionRow({required this.title, required this.trailingText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      title: title,
      trailingText: trailingText,
      onTap: onTap,
    );
  }
}

class _SettingsStyles {
  static TextStyle get title => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.black87,
        height: 1.1,
        letterSpacing: 0,
      );

  static TextStyle get trailing => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF757575),
        height: 1.15,
        letterSpacing: 0,
      );

  static TextStyle get counter => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
        height: 1.0,
      );

  static TextStyle get menuItem => GoogleFonts.poppins(fontSize: 13, height: 1.0);
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({required this.title, this.trailingText, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE8E8E8), width: 0.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.settings, size: 18, color: Colors.black87),
                const SizedBox(width: 10),
                Expanded(
                  flex: trailingText == null ? 1 : 4,
                  child: Text(
                    title,
                    style: _SettingsStyles.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailingText != null && trailingText!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 5,
                    child: Text(
                      trailingText!,
                      style: _SettingsStyles.trailing,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      softWrap: true,
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WifiModeRow extends StatefulWidget {
  final SettingsViewModel vm;
  final AppStrings s;

  const _WifiModeRow({required this.vm, required this.s});

  @override
  State<_WifiModeRow> createState() => _WifiModeRowState();
}

class _WifiModeRowState extends State<_WifiModeRow> {
  String _deviceIp = '';

  @override
  void initState() {
    super.initState();
    _fetchIp();
  }

  Future<void> _fetchIp() async {
    try {
      final info = NetworkInfo();
      String? wifiIp = await info.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty) {
        if (mounted) setState(() => _deviceIp = wifiIp);
        return;
      }
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => _deviceIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.vm.localWifiModeEnabled;
    final String trailingText = enabled
        ? (_deviceIp.isNotEmpty ? 'http://$_deviceIp:8080/rfid-data' : widget.s.deviceIpNotFound)
        : widget.s.usingInternetConnection;

    return _SettingsTile(
      title: widget.s.localWifiMode,
      trailingText: trailingText,
      trailing: Switch(
        value: enabled,
        onChanged: (val) async {
          if (val) {
            await _fetchIp();
            if (_deviceIp.isNotEmpty) {
              await widget.vm.setLocalWifiModeEnabled(true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${widget.s.localWifiModeEnabledMsg}: http://$_deviceIp:8080/rfid-data'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.s.pleaseConnectToWifi), backgroundColor: Colors.orange),
                );
              }
            }
          } else {
            await widget.vm.setLocalWifiModeEnabled(false);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.s.internetModeEnabled), backgroundColor: Colors.green),
              );
            }
          }
        },
      ),
    );
  }
}

class _ReusableTagsRow extends StatelessWidget {
  final SettingsViewModel vm;
  final AppStrings s;

  const _ReusableTagsRow({required this.vm, required this.s});

  @override
  Widget build(BuildContext context) {
    final enabled = vm.webReusableTagEnabled;
    return _SettingsTile(
      title: s.reusableTags,
      trailingText: enabled ? s.singleReusableEnabled : s.onlyWebReusableEnabled,
      trailing: Switch(
        value: enabled,
        onChanged: (val) async {
          await vm.setWebReusableTagEnabled(val);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(val ? s.singleReusableEnabled : s.onlyWebReusableEnabled),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }
}

class _TrayModeRow extends StatefulWidget {
  final SettingsViewModel vm;
  final AppStrings s;

  const _TrayModeRow({required this.vm, required this.s});

  @override
  State<_TrayModeRow> createState() => _TrayModeRowState();
}

class _TrayModeRowState extends State<_TrayModeRow> {
  bool _busy = false;

  String _trailingText() {
    if (!widget.vm.trayModeEnabled) return widget.s.trayModeDisabled;
    final name = widget.vm.trayDeviceName.trim();
    if (name.isEmpty) return widget.s.selectTrayDevice;
    if (widget.vm.trayConnected) return '$name (${widget.s.trayConnected})';
    return '$name (${widget.s.trayNotConnected})';
  }

  Future<void> _pickTrayDevice() async {
    if (!await hasBluetoothPermissions()) {
      final granted = await requestBluetoothPermissions();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.s.bluetoothPermissionRequired), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    final devices = await widget.vm.listBondedTrayDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.s.noBondedBluetoothDevices), backgroundColor: Colors.orange),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(widget.s.selectTrayDevice, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (_, index) {
                    final device = devices[index];
                    return ListTile(
                      title: Text(device['name'] ?? ''),
                      subtitle: Text(device['address'] ?? ''),
                      onTap: () => Navigator.pop(ctx, device),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    final name = selected['name'] ?? 'Bluetooth Device';
    final address = selected['address'] ?? '';
    if (address.isEmpty) return;

    setState(() => _busy = true);
    await widget.vm.selectTrayDevice(name: name, address: address);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.s.trayDeviceSelected}: $name'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _setTrayMode(bool enabled) async {
    if (_busy) return;

    if (enabled) {
      if (!await hasBluetoothPermissions()) {
        final granted = await requestBluetoothPermissions();
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.s.bluetoothPermissionRequired), backgroundColor: Colors.orange),
          );
          return;
        }
      }

      var address = widget.vm.trayDeviceAddress.trim();
      if (address.isEmpty) {
        await _pickTrayDevice();
        address = widget.vm.trayDeviceAddress.trim();
        if (address.isEmpty) return;
      }
    }

    setState(() => _busy = true);
    await widget.vm.setTrayModeEnabled(enabled);
    await widget.vm.refreshTrayStatus();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? widget.s.trayModeEnabledMsg : widget.s.trayModeDisabledMsg,
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.vm.trayModeEnabled;
    return _SettingsTile(
      title: widget.s.trayMode,
      trailingText: _trailingText(),
      onTap: enabled ? _pickTrayDevice : null,
      trailing: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(
              value: enabled,
              onChanged: _setTrayMode,
            ),
    );
  }
}
