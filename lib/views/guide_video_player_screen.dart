import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/l10n_extension.dart';
import '../models/guide_video.dart';
import 'widgets/product_form_widgets.dart';

class GuideVideoPlayerScreen extends StatefulWidget {
  const GuideVideoPlayerScreen({super.key, required this.video});

  final GuideVideo video;

  @override
  State<GuideVideoPlayerScreen> createState() => _GuideVideoPlayerScreenState();
}

class _GuideVideoPlayerScreenState extends State<GuideVideoPlayerScreen> {
  VideoPlayerController? _videoController;
  WebViewController? _webController;
  bool _loading = true;
  bool _useWebView = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openUrl(widget.video.url);
    });
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  Future<void> _openUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      setState(() {
        _loading = false;
        _errorMsg = 'empty';
      });
      return;
    }

    if (widget.video.isYoutube) {
      _loadWebView(_youtubeEmbedUrl(url));
      return;
    }

    await _loadDirectVideo(url);
  }

  Future<void> _loadDirectVideo(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null || !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = 'invalid';
        });
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(parsed);
    _videoController = controller;
    controller.addListener(_onVideoTick);
    try {
      await controller.initialize();
      await controller.play();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _useWebView = false;
        _errorMsg = null;
      });
    } catch (_) {
      await controller.dispose();
      _videoController = null;
      if (!mounted) return;
      _loadWebView(url);
    }
  }

  void _loadWebView(String url) {
    _useWebView = true;
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _errorMsg = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _errorMsg = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    if (mounted) setState(() {});
  }

  static String _youtubeEmbedUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return raw;
    final host = uri.host.toLowerCase();
    String? videoId;
    if (host.contains('youtu.be')) {
      videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (host.contains('youtube.com')) {
      videoId = uri.queryParameters['v'];
      if (videoId == null || videoId.isEmpty) {
        final embedIndex = uri.pathSegments.indexOf('embed');
        if (embedIndex >= 0 && embedIndex + 1 < uri.pathSegments.length) {
          videoId = uri.pathSegments[embedIndex + 1];
        }
      }
    }
    if (videoId == null || videoId.isEmpty) return raw;
    return 'https://www.youtube.com/embed/$videoId?autoplay=1&rel=0&modestbranding=1';
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) return '${two(hours)}:${two(minutes)}:${two(seconds)}';
    return '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: productGradientAppBar(
        context: context,
        title: s.tr(widget.video.titleKey),
      ),
      body: Stack(
        children: [
          if (_useWebView && _webController != null)
            WebViewWidget(controller: _webController!)
          else if (_videoController != null && _videoController!.value.isInitialized)
            _buildNativePlayer()
          else
            const SizedBox.expand(),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_errorMsg != null && !_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.cannotOpenVideo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNativePlayer() {
    final controller = _videoController!;
    final value = controller.value;
    final durationMs = value.duration.inMilliseconds.toDouble();
    final duration = durationMs <= 0 ? 1.0 : durationMs;
    final position = value.position.inMilliseconds.toDouble().clamp(0.0, duration);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: () {
                if (value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                  if (!value.isPlaying)
                    const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 72,
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
              Text(
                _format(value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: position,
                  max: duration,
                  activeColor: const Color(0xFFD32940),
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    controller.seekTo(Duration(milliseconds: v.round()));
                  },
                ),
              ),
              Text(
                _format(value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
