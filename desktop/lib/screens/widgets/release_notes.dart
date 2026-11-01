import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Release notes, written in Markdown on Gitea or GitHub, rendered the way
/// those sites show them: headings, lists, bold, code and links (which open
/// in the browser).
class ReleaseNotes extends StatelessWidget {
  final String markdown;
  final TextStyle? textStyle;

  const ReleaseNotes(this.markdown, {super.key, this.textStyle});

  /// GitHub-flavoured Markdown to HTML. Exposed for tests.
  static String toHtml(String markdown) => md.markdownToHtml(
        markdown.trim(),
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      toHtml(markdown),
      textStyle: textStyle,
      onTapUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
          return true; // handled: ignore anything that isn't a web link
        }
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          // Nothing more to do; the link text is still visible.
        }
        return true;
      },
    );
  }
}
