# Technical Troubleshooting Workaround Bank — FlowInCash & Teller Integrations

## Issue 1: React Native / Expo Invariant Startup Crash
- **Symptom**: Standalone release APK mounts and immediately closes back to the phone's homescreen, leaving no logs in development console.
- **Root Cause**: The React Native native wrapper is built to boot the entry component name `"main"` (`MainActivity.kt`'s `getMainComponentName()`). However, JavaScript registers the starting component under the package variable name `"flowincash-mobile"` (read from `package.json`). The name mismatch causes a direct native Invariant Violation crash on launch.
- **Fix**: Update the JavaScript entry file (`index.js`) to target the native compilation name directly:
  ```js
  AppRegistry.registerComponent('main', () => App);
  ```

## Issue 2: Offline Crash on Standard Start (Firebase/Sentry)
- **Symptom**: Standing production builds flash and close when launched offline (unplugged from internet/cellular data).
- **Root Cause**: Startup tasks such as Sentry reading empty constants (`Constants.expoConfig?.extra?.sentryDsn` is null when offline) or Firebase/Notification setups calling Google Play Services throw unhandled network resolution exceptions. These crash the startup thread instantly.
- **Fix**: Protect environment checks with fallbacks and wrap Firebase/Sentry startup calls in strict connection/existence guards:
  ```ts
  const extra = Constants.expoConfig?.extra || {};
  const sentryDsn = extra.sentryDsn; // guard from undefined crash
  ```

## Issue 3: Missing Database Tables (Tenant Context / Audit Trail)
- **Symptom**: Desktop Web App returns an generic `Request Failed` (HTTP 500) during login or account setup.
- **Root Cause**:
  1. Multitenancy controllers require `coreClient.setTenantContext()` to be run, but newer security/forecast modules call the API directly without assigning context.
  2. Authenticators seek to save logs to `audit_trail` table, but the table columns (or the tables themselves) were never fully migrated into the local database schema.
- **Fix**: Run migrations `014_audit_trail.sql` and `020_teller_integration.sql` directly on the local database schema, reset failed attempt lockouts, and ensure global auth headers automatically set tenant properties.
