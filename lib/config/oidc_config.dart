class OidcConfig {
  static const authority = 'https://auth.gamepowerx.com';
  static const clientId = 'schuly-mobile';
  // `offline_access` is required for Pocket ID to issue a refresh token —
  // without it the silent token refresh has nothing to work with and the user
  // gets bounced to re-login the moment the access token expires.
  static const scope = 'openid profile email groups picture offline_access';

  // Custom scheme deep link. Pocket ID redirects here after login; Android
  // routes it back to the app via the schulytest:// intent filter, so the
  // user lands in the real Chrome (full passkey support) and returns to the
  // app on success. Scheme intentionally does NOT mirror the package id so
  // dev and prod flavors can coexist.
  static const redirectUri = 'schulytest://callback';
  static const callbackScheme = 'schulytest';

  // Backend base URL. Override per build for local/dev runs:
  //   flutter build apk --dart-define=BACKEND_BASE_URL=http://<dev-box-lan-ip>:5033
  static const backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://schuly.gamepowerx.com',
  );

  static const tokenEndpoint = '$authority/api/oidc/token';
  static const authorizationEndpoint = '$authority/api/oidc/authorization';

  /// Resolves a backend-supplied URL: absolute (http…) is used as-is, a
  /// root-relative path (/api/avatars/…) is prefixed with [backendBaseUrl],
  /// null/empty returns null. Signed capability URLs need no auth header.
  static String? resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '$backendBaseUrl$url';
    return url;
  }
}
