import 'package:flutter/material.dart';

/// Loads a deferred library then builds the screen (keeps cold start small).
class DeferredScreen extends StatefulWidget {
  final Future<void> Function() loadLibrary;
  final Widget Function() builder;

  const DeferredScreen({
    super.key,
    required this.loadLibrary,
    required this.builder,
  });

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late final Future<void> _loadFuture = widget.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Text('Failed to load screen\n${snapshot.error}'),
            ),
          );
        }
        return widget.builder();
      },
    );
  }
}
