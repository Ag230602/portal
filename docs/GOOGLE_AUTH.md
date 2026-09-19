# Google authentication configuration and diagnosis

The application initiates Google OAuth with `supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo } })` in `github/supabase.ts`. The browser supplies only the Supabase project URL and publishable key. Supabase obtains the Google client ID and client secret from its managed Authentication provider configuration. Neither Google credential belongs in the frontend source, frontend variables, GitHub Pages HTML, or database profile metadata.

## Investigation of the reported invalid_client error

The existing source contained no hard-coded Google OAuth client ID or client secret. It did contain a fallback Supabase project URL, which has been removed. Both Supabase build variables are now required and validated.

A read-only trace of the live Supabase authorization endpoint returned a redirect to accounts.google.com using a configured Google client ID with the expected `.apps.googleusercontent.com` suffix. The Google callback was already correct:

`https://yhzrflaunlqmmlgxrthr.supabase.co/auth/v1/callback`

Correct formatting does not establish that a client still exists. Google's reported `401 invalid_client / OAuth client was not found` must be resolved by verifying the real Web application OAuth client in Google Cloud and updating Supabase's Google provider configuration. This cannot be fixed by inventing an ID or changing the portal redirect URL. No Google credentials were supplied to this coding session, so provider credentials have not been replaced.

## Required browser configuration

| Environment variable | Value source |
| --- | --- |
| `VITE_SUPABASE_URL` | Supabase project URL |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Supabase publishable key, or legacy `anon` key |

For local development, copy `github/.env.example` to `github/.env.local` and supply real values. Run `npm run dev:github`; the configured local address is `http://127.0.0.1:5173/`. `http://localhost:5173/` also works if the host resolves to the same server.

For GitHub Pages, set these two values in repository Settings → Secrets and variables → Actions → Variables. The build derives the project-site base path from the GitHub Actions repository context. Root sites and sites with `public/CNAME` use `/`; `GITHUB_PAGES_BASE` can explicitly override the base path. Changes to build-time settings require a fresh deployment. These values are browser-visible by design; authorization is enforced by Supabase JWT validation, the `naac_members` table, RPC permission checks, and storage/database policies. The app rejects service-role and secret API keys in the browser.

## Correct the managed Google provider

1. Open Google Cloud → Google Auth Platform → Clients. Locate or create the actual **Web application** OAuth client. Check that its client ID exists in the intended Google Cloud project and has not been deleted. Do not use an API key, project number, Android client ID, or a placeholder.
2. Set the Google client's authorized redirect URI to the Supabase callback above. The callback is **not** a GitHub Pages dashboard URL or an application `/callback` route.
3. In Supabase → Authentication → Sign In / Providers → Google, enable Google and enter the matching Google Client ID and Client Secret from that client. Keep the secret only in this secure provider configuration.
4. In Supabase Authentication → URL Configuration, set Site URL to `https://ag230602.github.io/portal/` and add these exact Redirect URLs:
   - `https://ag230602.github.io/portal/`
   - `http://localhost:5173/`
   - `http://127.0.0.1:5173/`
5. If using a custom production domain, add its application-root URL too. The portal derives `redirectTo` from the current browser origin and the deployment base path, so localhost is never replaced by the production domain.
6. For access by anyone with a Google account, configure Google's external audience appropriately. While Google's application is in testing, only configured test users may be able to complete consent.

Use standard `openid`, email, and profile scopes. Do not add unrelated Google data permissions.

## Environment-based operator setup

To configure the managed provider without putting Google credentials in frontend code, use `scripts/configure-google-auth.mjs`. Supply these values securely in the operator environment or a gitignored environment file:

- `SUPABASE_ACCESS_TOKEN`: operator's Supabase management token with access to this project
- `SUPABASE_PROJECT_REF`: `yhzrflaunlqmmlgxrthr`
- `GOOGLE_CLIENT_ID`: real Web application OAuth client ID
- `GOOGLE_CLIENT_SECRET`: matching secret

Run `npm run auth:check` to list missing variables without changing the project. Run `node scripts/configure-google-auth.mjs --apply` only after configuring the real values. For a gitignored environment file, Node 22 supports `node --env-file=.env scripts/configure-google-auth.mjs --check` or `--apply`. The utility never logs values and changes only the Google provider configuration. Callback/redirect URL configuration still needs to be checked as above.

These are operator variables used to provision Supabase. The deployed static website never reads Google credentials directly. Supabase's hosted Auth service securely stores and uses the provider settings.

## Session and role routing

The Supabase singleton handles PKCE callback processing and session persistence. Bootstrap waits for session initialization and then verifies the user with `getUser()`. The existing `naac_portal('load')` RPC obtains the role from `public.naac_members`; URL parameters and user-editable Google profile metadata cannot assign roles.

| Profile role | Application route |
| --- | --- |
| `respondent` or `student` | `/student/dashboard` |
| `coordinator` | `/coordinator/dashboard` |
| `admin` | `/admin/dashboard` |

For this GitHub project site the deployment prefix is retained, e.g. `https://ag230602.github.io/portal/admin/dashboard`. With a root-domain deployment it is `/admin/dashboard`. Dashboard index files are emitted so refreshing or bookmarking these paths works on GitHub Pages. Typing another role's URL does not grant permissions: after authentication the app replaces it with the route matching the database profile, and all data operations retain their existing server-side permission checks.

Respondents without a department still complete the existing onboarding screen. Annexure forms, evidence upload/download, reporting, coordinator approval, and administration use the unchanged transport interface. Signing out in another tab clears the displayed workspace.

OAuth errors returned in query parameters or fragments are converted to professional messages, and error tokens/codes are removed from the address bar. A Google-hosted error screen cannot be intercepted by portal JavaScript before Google returns control; the provider configuration must be corrected for `invalid_client` at Google.

References: https://supabase.com/docs/guides/auth/social-login/auth-google and https://supabase.com/docs/guides/auth/redirect-urls
