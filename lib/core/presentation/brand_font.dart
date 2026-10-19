import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Clash Grotesk, the typeface of badrgo.com.
///
/// Its licence (ITF Free Font License) forbids redistributing the font
/// files, so they are not in this repo. The app loads them from Fontshare's
/// own servers at start-up, which the licence allows. If that fails (offline,
/// blocked), headings fall back to the default font.
class BrandFont {
  const BrandFont._();

  static const family = 'Clash Grotesk';

  static final _cssUrl = Uri.parse('https://api.fontshare.com/v2/css?f[]=clash-grotesk@400,500,600&display=swap');

  /// Registers the regular, medium and semibold weights. Never throws.
  static Future<bool> load(http.Client client, {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final css = await client.get(_cssUrl).timeout(timeout);
      if (css.statusCode != 200) return false;
      final urls = RegExp(r"url\('([^']+\.ttf)'\)").allMatches(css.body).map((m) => m.group(1)!).toList();
      if (urls.isEmpty) return false;
      final loader = FontLoader(family);
      for (final url in urls) {
        // The engine reads each file's own weight, so one family covers all.
        loader.addFont(_fetch(client, url.startsWith('//') ? 'https:$url' : url, timeout));
      }
      await loader.load().timeout(timeout);
      return true;
    } on Object {
      return false;
    }
  }

  static Future<ByteData> _fetch(http.Client client, String url, Duration timeout) async {
    final response = await client.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) throw http.ClientException('Font ${response.statusCode}', Uri.parse(url));
    return ByteData.sublistView(response.bodyBytes);
  }
}
