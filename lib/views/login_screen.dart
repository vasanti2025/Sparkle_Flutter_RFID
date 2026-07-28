import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/login_view_model.dart';
import '../viewmodels/product_view_model.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/curved_header_painter.dart';

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
  LoginViewModel? _loginVm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fieldsInitialized) return;
    _fieldsInitialized = true;
    final pref = context.read<PrefService>();
    if (pref.getSavedUsername().isNotEmpty) {
      _usernameController.text = pref.getSavedUsername();
      _passwordController.text = pref.getSavedPassword();
    }
    final viewModel = context.read<LoginViewModel>();
    _loginVm = viewModel;
    viewModel.addListener(_onLoginVmChanged);
    if (_usernameController.text.isEmpty && viewModel.username.isNotEmpty) {
      _usernameController.text = viewModel.username;
      _passwordController.text = viewModel.password;
    }
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
    if (viewModel.rememberMe) {
      _usernameController.text = viewModel.username;
      _passwordController.text = viewModel.password;
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
    if (err != null && err != _lastShownError) {
      _lastShownError = err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.red),
        );
        viewModel.clearErrorMessage();
      });
    }
  }

  void _showCustomApiDialog(BuildContext context, LoginViewModel viewModel) {
    final s = context.sRead;
    _apiController.text = viewModel.getCustomApiUrl();

    showDialog<void>(
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
                      colors: [Color(0xFF5231A7), Color(0xFFD32940)],
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
                            borderSide: const BorderSide(color: Color(0xFF5231A7), width: 1.5),
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
                              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
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
    showDialog(
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
                        final productVm = context.read<ProductViewModel>();
                        final stockVm = context.read<StockTransferViewModel>();
                        final dashVm = context.read<DashboardViewModel>();
                        Navigator.pushReplacementNamed(context, '/dashboard');
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          stockVm.resetSession();
                          dashVm.loadUser();
                          Future<void>.delayed(const Duration(seconds: 1), () {
                            unawaited(productVm.syncProducts(force: true));
                          });
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF315BA3),
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

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final viewModel = context.watch<LoginViewModel>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Custom Wave Curved Header
            SizedBox(
              width: double.infinity,
              height: 285,
              child: CustomPaint(
                painter: CurvedHeaderPainter(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      s.welcomeTo,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      s.sparkleRfid,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      s.pleaseLoginToContinue,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    // Tab Buttons: Password vs Face
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => viewModel.setLoginMode('password'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: viewModel.selectedLoginMode == 'password'
                                      ? const LinearGradient(
                                          colors: [Color(0xFF315BA3), Color(0xFFA7192E)],
                                        )
                                      : const LinearGradient(
                                          colors: [Color(0xFFE0E0E0), Color(0xFFCCCCCC)],
                                        ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  s.password,
                                  style: TextStyle(
                                    color: viewModel.selectedLoginMode == 'password'
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => viewModel.setLoginMode('face'),
                            child: Container(
                              width: 56,
                              height: 50,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: viewModel.selectedLoginMode == 'face'
                                      ? const LinearGradient(
                                          colors: [Color(0xFF315BA3), Color(0xFFA7192E)],
                                        )
                                      : const LinearGradient(
                                          colors: [Color(0xFFE0E0E0), Color(0xFFCCCCCC)],
                                        ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.face,
                                size: 28,
                                color: viewModel.selectedLoginMode == 'face'
                                    ? Colors.white
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (viewModel.selectedLoginMode == 'password') ...[
                      // Username Input
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _usernameController,
                          onChanged: viewModel.setUsername,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: s.usernameLabel,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password Input
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _passwordController,
                          onChanged: viewModel.setPassword,
                          obscureText: !viewModel.passwordVisible,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: s.password,
                            suffixIcon: IconButton(
                              icon: Icon(
                                viewModel.passwordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.grey,
                              ),
                              onPressed: viewModel.togglePasswordVisibility,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Remember Me & Forgot Password
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: viewModel.rememberMe,
                                  onChanged: (val) {
                                    if (val != null) viewModel.setRememberMe(val);
                                  },
                                ),
                                Text(
                                  s.rememberMe,
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                            Text(
                              s.forgotPassword,
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Face login message and lock icon
                      const SizedBox(height: 24),
                      Text(
                        s.useFaceDetectionLogin,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Icon(
                        Icons.face_unlock_rounded,
                        size: 72,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 20),
                    ],

                    const SizedBox(height: 16),

                    // Login Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: GestureDetector(
                        onTap: viewModel.isLoading
                            ? null
                            : () async {
                                if (viewModel.selectedLoginMode == 'password') {
                                  final success = await viewModel.login(context);
                                  if (success && context.mounted) {
                                    final productVm = context.read<ProductViewModel>();
                                    final stockVm = context.read<StockTransferViewModel>();
                                    final dashVm = context.read<DashboardViewModel>();
                                    Navigator.pushReplacementNamed(context, '/dashboard');
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      stockVm.resetSession();
                                      dashVm.loadUser();
                                      Future<void>.delayed(const Duration(seconds: 1), () {
                                        unawaited(productVm.syncProducts(force: true));
                                      });
                                    });
                                  }
                                } else {
                                  // Navigate to Face detection placeholder
                                  Navigator.pushNamed(context, '/face_login');
                                }
                              },
                        child: Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF315BA3), Color(0xFFA7192E)],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: viewModel.isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                )
                              : Text(
                                  viewModel.selectedLoginMode == 'password'
                                      ? s.logIn
                                      : s.logInWithFace,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Trouble Logging In?
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.troubleLogin,
                          style: TextStyle(color: Colors.grey),
                        ),
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.contactUsClicked)),
                            );
                          },
                          child: Text(
                            s.contactUs,
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Configure Custom API
                    GestureDetector(
                      onTap: () => _showCustomApiDialog(context, viewModel),
                      child: Text(
                        s.configureCustomApi,
                        style: TextStyle(
                          color: const Color(0xFF5231A7),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFF5231A7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
