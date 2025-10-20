# Frontend — React SPA (`apps/web`)

## Stack & Tooling
- React 19 + React Router 7, rendered through Vite 7 with TypeScript strict mode.
- Tailwind CSS 4 via `@tailwindcss/postcss` and a minimal `tailwind.config.ts`.
- Local state only; no global store. Data refresh is handled with React hooks and the Fetch API.
- Build + lint scripts live in `apps/web/package.json`; repo-level workflows call them through `npm`.

## Project Layout
- `src/main.tsx` wires `BrowserRouter` routes and guards everything except `/login`, `/auth/callback`, and `/logout`.
- `src/App.tsx` is the single page rendered after auth; it fetches health + holdings, displays status badges, and exposes a `Refresh` CTA.
- `src/api/client.ts` centralises API calls, applies the Cognito ID token header, and forces a redirect on `401/403`.
- `src/auth/auth.ts` implements the Cognito Hosted UI PKCE loop (see below) and persists tokens in `localStorage`.
- `src/components/Badge.tsx` and `src/components/HoldingsTable.tsx` are lightweight UI primitives.
- `src/types.ts` mirrors the backend response models so the UI stays type-safe when parsing JSON.

## Authentication Flow (Cognito Hosted UI)
1. `/login` immediately calls `login()` which generates PKCE `state` + `code_verifier`, stores them in `sessionStorage`, and redirects to Cognito.
2. Cognito redirects back to `/auth/callback?code=...&state=...`; `handleCallback()` exchanges the code for tokens, validates the `state`, and stores `id_token`, `access_token`, and `expires_at` in `localStorage`.
3. A successful callback rewrites the URL to `/` so the SPA renders the protected app without query params.
4. `logout()` clears stored tokens and sends the browser to Cognito’s `/logout` endpoint with the configured post-logout URI.

`Protected` in `main.tsx` uses `isAuthed()` to gate the rest of the router tree, so expired tokens will bounce the user back to `/login`.

## Data Fetching & Error Handling
- `App.tsx` kicks off both `getHealth()` and `getHoldings()` on mount via an `AbortController`; the health check runs best-effort in parallel.
- `getHoldings({ refresh: true })` appends `?refresh=1`, which the backend interprets as a cache bypass.
- API helpers automatically normalise headers and redirect to `/login` when Cognito sessions expire.
- Errors bubble into local component state: a toast-style inline message appears next to the refresh button so users can retry.

## Styling
- Tailwind utility classes drive layout; global styles are limited to `index.css` (Tailwind import, light mode, basic button tweaks).
- Components favour semantic HTML (`table`, `button`) so the SPA renders well even without JavaScript enhancements.

## Environment Variables

| Variable | Purpose | Example |
| --- | --- | --- |
| `VITE_API_BASE` | API Gateway base URL used for all fetches | `example-val` |
| `VITE_COGNITO_DOMAIN` | Cognito Hosted UI domain (no protocol) | `example-val` |
| `VITE_COGNITO_CLIENT_ID` | SPA client ID registered in Cognito | `example-val` |
| `VITE_COGNITO_REGION` | AWS region for Cognito; used mainly for logging/debug | `example-val` |
| `VITE_COGNITO_REDIRECT_URI` | Where Cognito sends users after login | `example-val` |
| `VITE_COGNITO_LOGOUT_URI` | Post-logout landing page | `example-val` |

Define these in `.env` (for local dev) or rely on Terraform outputs + the `just web-build` recipe during CI/CD.

## Local Development
```bash
cd apps/web
npm ci          # one-time dependency install
npm run dev     # Vite dev server on http://localhost:5173

npm run lint    # ESLint flat config
npm run build   # TypeScript project refs + Vite production build
```

- The dev server expects a running backend reachable at `VITE_API_BASE`; for rapid UI work you can stub JSON responses with a local proxy.
- To exercise auth locally, configure Cognito to allow `http://localhost:5173/auth/callback` in its redirect URIs.

## Production Build & Deploy
- `npm run build` emits the SPA to `apps/web/dist`.
- `just web-build` wraps the build with environment validation so CI fails fast if secrets are missing.
- `just web-deploy-s3` syncs the built assets to the CloudFront S3 bucket and invalidates the distribution (keeps `index.html` uncached).

## Troubleshooting
- **Stuck redirect loop?** Clear `localStorage` / `sessionStorage` for the domain to reset PKCE state and tokens.
- **401 after login?** Ensure the CloudFront origin matches the Cognito app client’s allowed origins; mismatches block cookies and tokens.
- **Build fails on missing env vars?** Confirm `.env` is loaded (repo `set dotenv-load := true`) or export values before invoking `just web-build`.
- **Styles missing?** Tailwind requires the PostCSS plugin; rerun `npm ci` after dependency changes to regenerate `.postcssrc.cjs` cache.
