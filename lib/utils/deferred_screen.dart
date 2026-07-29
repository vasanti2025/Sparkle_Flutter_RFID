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
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Full-screen white — avoids tiny spinner → full page "zoom" jump.
          return const Scaffold(
            backgroundColor: Colors.white,
            body: SizedBox.expand(),
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
        _built ??= widget.builder();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: const ValueKey('deferred-loaded'),
            child: _built!,
          ),
        );
      },
    );
  }
}
