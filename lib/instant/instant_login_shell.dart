import 'package:flutter/material.dart';

/// Ultra-light login chrome — only Material widgets, paints on frame 1.
class InstantLoginShell extends StatelessWidget {
  final String username;
  final String password;

  const InstantLoginShell({
    super.key,
    this.username = '',
    this.password = '',
  });

  static const _brand = Color(0xFF5231A7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ColoredBox(
            color: _brand,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    'Sparkle RFID',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Username',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 6),
                _fakeField(username.isEmpty ? ' ' : username),
                const SizedBox(height: 16),
                const Text(
                  'Password',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 6),
                _fakeField(password.isEmpty ? '••••••' : '••••••••'),
                const SizedBox(height: 32),
                const ColoredBox(
                  color: _brand,
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        'Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
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
    );
  }

  Widget _fakeField(String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFFFAFAFA),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: const TextStyle(fontSize: 15, color: Color(0xFF212121)),
        ),
      );
}
