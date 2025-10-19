const DOMAIN = import.meta.env.VITE_COGNITO_DOMAIN;
const CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID;
const REDIRECT_URI = import.meta.env.VITE_COGNITO_REDIRECT_URI;
const LOGOUT_URI = import.meta.env.VITE_COGNITO_LOGOUT_URI;

const KEY = {
  verifier: "pkce_verifier",
  state: "oauth_state",
  id: "id_token",
  access: "access_token",
  expires: "expires_at",
} as const;

export function getIdToken() {
  return localStorage.getItem(KEY.id) || "";
}
export function isAuthed() {
  return (
    !!getIdToken() &&
    Date.now() < Number(localStorage.getItem(KEY.expires) || 0)
  );
}
export type HeaderMap = Record<string, string>;

export function authHeader(): HeaderMap {
  const h: HeaderMap = {};
  const id = localStorage.getItem(KEY.id);
  const exp = Number(localStorage.getItem(KEY.expires) || 0);
  if (id && Date.now() < exp) {
    h.Authorization = `Bearer ${id}`;
  }
  return h;
}

import { randomString, sha256 } from "./pkce";

export async function login() {
  const state = randomString(16);
  const verifier = randomString(64);
  const challenge = await sha256(verifier);

  sessionStorage.setItem(KEY.state, state);
  sessionStorage.setItem(KEY.verifier, verifier);

  const authUrl = new URL(`https://${DOMAIN}/oauth2/authorize`);
  authUrl.searchParams.set("client_id", CLIENT_ID);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", "openid email profile");
  authUrl.searchParams.set("redirect_uri", REDIRECT_URI);
  authUrl.searchParams.set("code_challenge_method", "S256");
  authUrl.searchParams.set("code_challenge", challenge);
  authUrl.searchParams.set("state", state);

  window.location.assign(authUrl.toString());
}

export async function handleCallback() {
  const params = new URLSearchParams(window.location.search);
  const code = params.get("code");
  const state = params.get("state");
  if (!code) return false;

  const storedState = sessionStorage.getItem(KEY.state);
  if (!storedState || storedState !== state) throw new Error("Invalid state");

  const verifier = sessionStorage.getItem(KEY.verifier) || "";
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: CLIENT_ID,
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
  });

  const resp = await fetch(`https://${DOMAIN}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!resp.ok) throw new Error(`Token exchange failed: ${resp.status}`);
  const tok = await resp.json();

  localStorage.setItem(KEY.id, tok.id_token);
  localStorage.setItem(KEY.access, tok.access_token);
  const expiresAt = Date.now() + (tok.expires_in * 1000 - 5000);
  localStorage.setItem(KEY.expires, String(expiresAt));

  // cleanup PKCE + URL
  sessionStorage.removeItem(KEY.state);
  sessionStorage.removeItem(KEY.verifier);
  history.replaceState({}, "", "/"); // or navigate('/') in your callback route

  return true;
}

export function logout() {
  localStorage.removeItem(KEY.id);
  localStorage.removeItem(KEY.access);
  localStorage.removeItem(KEY.expires);

  const url = new URL(`https://${DOMAIN}/logout`);
  url.searchParams.set("client_id", CLIENT_ID);
  url.searchParams.set("logout_uri", LOGOUT_URI); // e.g., https://<CF>/login or /logged-out
  window.location.assign(url.toString());
}
