import 'package:flutter/material.dart';

class MediaViewer extends StatelessWidget {
  final String url;
  final String title;

  const MediaViewer({
    super.key,
    required this.url,
    required this.title,
  });

  static Future<void> show(BuildContext context, String url, String title) {
    return showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => MediaViewer(url: url, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.white54, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'Could not load image',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
