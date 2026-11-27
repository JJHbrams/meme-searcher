import 'models.dart';

// Keep in sync with the standalone MCP's source filter.
const _hiddenHosts = {'ilbe.com', 'megalian.com'};

bool hasHiddenMemeSource(MemeAsset asset) =>
    [
      asset.sourceUrl,
      asset.originalUrl,
      asset.previewUrl,
      asset.discoveryUrl,
    ].whereType<String>().any((value) {
      final host = Uri.tryParse(value.trim())?.host.toLowerCase() ?? '';
      final canonical = host.endsWith('.')
          ? host.substring(0, host.length - 1)
          : host;
      return _hiddenHosts.any(
        (domain) => canonical == domain || canonical.endsWith('.$domain'),
      );
    });
