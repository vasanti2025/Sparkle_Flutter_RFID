import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/login_view_model.dart';
import '../utils/app_fonts.dart';
import '../utils/user_facing_error.dart';
import '../session_vm_hooks.dart' deferred as vm_hooks;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _apiController = TextEditingController();
  bool _expiryDialogQueued = false;
  String? _lastShownError;
  bool _fieldsInitialized = false;
  bool _rememberFieldsApplied = false;
  LoginViewModel? _loginVm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fieldsInitialized) return;
    _fieldsInitialized = true;
    final pref = context.read<PrefService>();
    if (pref.getSavedUsername().isNotEmpty) {
      _applyRememberMeFields(
        pref.getSavedUsername(),
        pref.getSavedPassword(),
      );
    }
    final viewModel = context.read<LoginViewModel>();
    _loginVm = viewModel;
    viewModel.addListener(_onLoginVmChanged);
    if (_usernameController.text.isEmpty && viewModel.username.isNotEmpty) {
      _applyRememberMeFields(viewModel.username, viewModel.password);
    }
  }

  void _applyRememberMeFields(String username, String password) {
    if (_rememberFieldsApplied) return;
    _usernameController.value = TextEditingValue(
      text: username,
      selection: TextSelection.collapsed(offset: username.length),
    );
    _passwordController.value = TextEditingValue(
      text: password,
      selection: TextSelection.collapsed(offset: password.length),
    );
    _loginVm?.setUsername(username);
    _loginVm?.setPassword(password);
    _rememberFieldsApplied = true;
  }

  @override
  void dispose() {
    _loginVm?.removeListener(_onLoginVmChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _apiController.dispose();
    super.dispose();
  }

  void _onLoginVmChanged() {
    if (!mounted || _loginVm == null) return;
    final viewModel = _loginVm!;
    // Only pre-fill once from Remember Me — never overwrite while user is typing.
    if (viewModel.rememberMe &&
        !_rememberFieldsApplied &&
        _usernameController.text.isEmpty &&
        _passwordController.text.isEmpty) {
      _applyRememberMeFields(viewModel.username, viewModel.password);
    }
    if (viewModel.showExpiryWarning && !_expiryDialogQueued) {
      _expiryDialogQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showExpiryWarningDialog(context, viewModel);
        _expiryDialogQueued = false;
      });
    }
    final err = viewModel.errorMessage;
    if (err == null || err.isEmpty) {
      if (_lastShownError != null) {
        _lastShownError = null;
        _clearLoginSnackBars();
      }
      return;
    }
    if (err == _lastShownError) return;
    _lastShownError = err;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Login succeeded (or error was cleared) before this frame — do not show it.
      final current = _loginVm?.errorMessage;
      if (current == null || current.isEmpty || current != err) {
        _clearLoginSnackBars();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.fromMessage(err)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void _clearLoginSnackBars() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  void _navigateAfterLogin(BuildContext context) {
    _lastShownError = null;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.sRead.loginSuccess),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.pushReplacementNamed(context, '/dashboard');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      try {
        context.read<DashboardViewModel>().loadUser();
      } catch (_) {}
      try {
        await vm_hooks.loadLibrary();
        if (!context.mounted) return;
        vm_hooks.resetStockTransferSession(context);
        vm_hooks.startProductSyncAfterLogin(context);
      } catch (_) {}
    });
  }

  void _showCustomApiDialog(BuildContext context, LoginViewModel viewModel) {
    final s = context.sRead;
    _apiController.text = viewModel.getCustomApiUrl();

    showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFF3A3228)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.configureCustomApi,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.apiUrlAuthorizedMessage,
                        style: TextStyle(
                          color: const Color(0xFF666666),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s.enterApiUrl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF222222),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiController,
                        keyboardType: TextInputType.url,
                        style: TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: s.customApiUrlHint,
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFC4A35A), width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFD0D0D0)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            s.cancel,
                            style: TextStyle(
                              color: const Color(0xFF666666),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1A1A1A), Color(0xFF3A3228)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              viewModel.saveCustomApiUrl(_apiController.text.trim());
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(s.customApiSaved)),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(
                              s.save,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExpiryWarningDialog(BuildContext context, LoginViewModel viewModel) {
    final s = context.sRead;
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: roundedCornerShape(12),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          title: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF3A3A3A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  s.expiryWarning,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          content: Text(
            viewModel.expiryWarningMessage,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      viewModel.cancelExpiryLogin();
                      Navigator.pop(context);
                    },
                    child: Text(
                      s.cancel,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await viewModel.confirmExpiryAndLogin();
                      if (context.mounted) {
                        _navigateAfterLogin(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                    ),
                    child: Text(
                      s.continueLabel,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  RoundedRectangleBorder roundedCornerShape(double radius) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
  }

  void _contactSupport() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.sRead.contactUsClicked)),
    );
  }

  InputDecoration _fieldDecoration({Widget? suffix}) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0xFFDCD8D0)),
    );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      suffixIcon: suffix,
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF94702E), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final viewModel = context.watch<LoginViewModel>();
    final label = AppFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF20201F),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F2),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: const ColoredBox(
                          color: Color(0xFF111111),
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Image(
                              image: AssetImage('assets/branding/splash_logo_white.png'),
                              width: 46,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.sparkleRfid.toUpperCase(),
                              style: AppFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: const Color(0xFF20201F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.brandByline,
                              style: AppFonts.poppins(
                                fontSize: 10,
                                color: const Color(0xFF6D6B66),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/face_login'),
                        icon: const Icon(
                          Icons.face_retouching_natural,
                          size: 22,
                        ),
                        color: const Color(0xFF20201F),
                        tooltip: s.logInWithFace,
                      ),
                      IconButton(
                        onPressed: _contactSupport,
                        icon: const Icon(Icons.help_outline, size: 22),
                        color: const Color(0xFF20201F),
                        tooltip: s.contactUs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    s.welcomeBack,
                    style: AppFonts.poppins(
                      fontSize: 29,
                      fontWeight: FontWeight.w600,
                      height: 1.12,
                      color: const Color(0xFF20201F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.signInLead,
                    style: AppFonts.poppins(
                      fontSize: 14,
                      height: 1.6,
                      color: const Color(0xFF6D6B66),
                    ),
                  ),
                  const SizedBox(height: 27),
                  Text(s.usernameLabel, style: label),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    onChanged: (value) {
                      _rememberFieldsApplied = true;
                      _lastShownError = null;
                      viewModel.clearErrorMessage();
                      viewModel.setUsername(value);
                    },
                    autocorrect: false,
                    enableSuggestions: false,
                    style: AppFonts.poppins(fontSize: 16),
                    decoration: _fieldDecoration(),
                  ),
                  const SizedBox(height: 19),
                  Text(s.password, style: label),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    onChanged: (value) {
                      _rememberFieldsApplied = true;
                      _lastShownError = null;
                      viewModel.clearErrorMessage();
                      viewModel.setPassword(value);
                    },
                    obscureText: !viewModel.passwordVisible,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: AppFonts.poppins(fontSize: 16),
                    decoration: _fieldDecoration(
                      suffix: IconButton(
                        icon: Icon(
                          viewModel.passwordVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF6D6B66),
                        ),
                        onPressed: viewModel.togglePasswordVisibility,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: viewModel.rememberMe,
                          activeColor: const Color(0xFF282825),
                          onChanged: (val) {
                            if (val != null) viewModel.setRememberMe(val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.rememberMe,
                        style: AppFonts.poppins(fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        s.forgotPassword,
                        style: AppFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF866526),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: viewModel.isLoading
                          ? null
                          : () async {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _lastShownError = null;
                              _clearLoginSnackBars();
                              viewModel.clearErrorMessage();
                              final success = await viewModel.login(
                                context,
                                username: _usernameController.value.text,
                                password: _passwordController.value.text,
                              );
                              if (!mounted) return;
                              if (success) {
                                _navigateAfterLogin(context);
                                return;
                              }
                              if ((viewModel.errorMessage ?? '').isNotEmpty) {
                                setState(() {});
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF20201E),
                        disabledBackgroundColor: const Color(0xFF20201E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: viewModel.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              s.logIn,
                              style: AppFonts.poppins(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _showCustomApiDialog(context, viewModel),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCD8D0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F5F2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.tune,
                                size: 18,
                                color: Color(0xFF866526),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.connectionSettings,
                                    style: AppFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF20201F),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.configureCustomApi,
                                    style: AppFonts.poppins(
                                      fontSize: 11,
                                      color: const Color(0xFF6D6B66),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Color(0xFF6D6B66),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
