import 'package:flutter/material.dart';

import '../auth/auth_manager.dart';
import 'instant_builder.dart';

/// Known OAuth providers with default labels/colors for [OAuthButton].
enum OAuthProvider {
  google('Continue with Google', Color(0xFF4285F4), Icons.g_mobiledata),
  apple('Continue with Apple', Color(0xFF000000), Icons.apple),
  github('Continue with GitHub', Color(0xFF24292E), Icons.code),
  linkedin('Continue with LinkedIn', Color(0xFF0A66C2), Icons.business),
  clerk('Continue with Clerk', Color(0xFF6C47FF), Icons.lock_outline),
  firebase('Continue with Firebase', Color(0xFFFFA000), Icons.local_fire_department);

  const OAuthProvider(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// A drop-in OAuth sign-in button that builds an InstantDB authorization URL
/// (with PKCE) and hands the resulting [OAuthFlow] to [onLaunch], which should
/// open the URL (e.g. via `url_launcher` or `flutter_web_auth_2`).
///
/// Keeping the launch in the app avoids forcing a `url_launcher` dependency on
/// the package while still wiring the full redirect flow. After the redirect
/// returns a `code`, call `db.auth.exchangeCodeForToken(code: ..., codeVerifier:
/// flow.codeVerifier)`.
///
/// ```dart
/// OAuthButton(
///   provider: OAuthProvider.google,
///   clientName: 'google',
///   redirectUri: 'myapp://oauth',
///   onLaunch: (flow) async {
///     final result = await FlutterWebAuth2.authenticate(
///       url: flow.url, callbackUrlScheme: 'myapp');
///     final code = Uri.parse(result).queryParameters['code']!;
///     await db.auth.exchangeCodeForToken(
///       code: code, codeVerifier: flow.codeVerifier);
///   },
/// )
/// ```
class OAuthButton extends StatelessWidget {
  /// Preset provider for default label/color/icon. Optional when [label] is set.
  final OAuthProvider? provider;

  /// OAuth client name configured in the InstantDB dashboard.
  final String clientName;

  /// Redirect URI registered for the client (e.g. a custom scheme).
  final String redirectUri;

  /// Called with the built [OAuthFlow]; open `flow.url` and complete sign-in.
  final Future<void> Function(OAuthFlow flow) onLaunch;

  final List<String>? scopes;
  final bool usePKCE;
  final String? label;
  final Color? color;
  final IconData? icon;

  const OAuthButton({
    super.key,
    this.provider,
    required this.clientName,
    required this.redirectUri,
    required this.onLaunch,
    this.scopes,
    this.usePKCE = true,
    this.label,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final text = label ?? provider?.label ?? 'Sign in';
    final bg = color ?? provider?.color ?? Theme.of(context).primaryColor;
    final iconData = icon ?? provider?.icon;

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
      ),
      onPressed: () async {
        final db = InstantProvider.of(context);
        final flow = db.auth.createAuthorizationUrl(
          clientName: clientName,
          redirectUri: redirectUri,
          usePKCE: usePKCE,
          scopes: scopes,
        );
        await onLaunch(flow);
      },
      icon: iconData != null ? Icon(iconData) : const SizedBox.shrink(),
      label: Text(text),
    );
  }
}
