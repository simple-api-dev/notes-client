/// Build-time configuration: the demo key and the shared demo account.
library;

/// The demo key baked in at build time:
///
///     flutter build web --dart-define=SIMPLEAPI_KEY=<your key>
///
/// It is empty when not provided. Never write a key in the source: anything
/// passed this way ends up in the compiled JavaScript, so use a free demo key.
const configuredKey = String.fromEnvironment('SIMPLEAPI_KEY');

// The shared demo account. Public by design: anyone may log in as this user.
const demoEmail = 'demo@simpleapi.dev';
const demoPassword = 'try-the-demo';

/// The SimpleAPI home page, opened by the back arrow.
const homeUrl = 'https://simpleapi.dev';
