import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../viewmodels/login_view_model.dart';
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

  @override
  void initState() {
    super.initState();
    // Pre-populate username and password if they were remembered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = Provider.of<LoginViewModel>(context, listen: false);
      _usernameController.text = viewModel.username;
      _passwordController.text = viewModel.password;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _apiController.dispose();
    super.dispose();
  }

  void _showCustomApiDialog(BuildContext context, LoginViewModel viewModel) {
    final s = context.sRead;
    _apiController.text = viewModel.getCustomApiUrl();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: roundedCornerShape(12),
          title: Text(
            s.configureCustomApi,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.apiUrlAuthorizedMessage,
                style: GoogleFonts.poppins(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _apiController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: s.enterApiUrl,
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      s.cancel,
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      viewModel.saveCustomApiUrl(_apiController.text);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.customApiSaved)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF315BA3),
                    ),
                    child: Text(
                      s.save,
                      style: GoogleFonts.poppins(color: Colors.white),
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
                  style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(
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
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await viewModel.confirmExpiryAndLogin();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/dashboard');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF315BA3),
                    ),
                    child: Text(
                      s.continueLabel,
                      style: GoogleFonts.poppins(color: Colors.white),
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

    // Listen for expiry warning dialog trigger
    if (viewModel.showExpiryWarning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showExpiryWarningDialog(context, viewModel);
      });
    }

    // Listen for error messages
    if (viewModel.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(viewModel.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
        viewModel.clearErrorMessage();
      });
    }

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
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      s.sparkleRfid,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      s.pleaseLoginToContinue,
                      style: GoogleFonts.poppins(
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
                                  style: GoogleFonts.poppins(
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
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                              ],
                            ),
                            Text(
                              s.forgotPassword,
                              style: GoogleFonts.poppins(
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
                        style: GoogleFonts.poppins(
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
                                    Navigator.pushReplacementNamed(context, '/dashboard');
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
                                  style: GoogleFonts.poppins(
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
                          style: GoogleFonts.poppins(color: Colors.grey),
                        ),
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.contactUsClicked)),
                            );
                          },
                          child: Text(
                            s.contactUs,
                            style: GoogleFonts.poppins(
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
                        style: GoogleFonts.poppins(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
