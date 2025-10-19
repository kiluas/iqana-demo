import type { HealthResponse, HoldingsResponse } from "../types";
import { getIdToken } from "../auth/auth";

// Keep this simple—no casts needed.
const API_BASE = (import.meta.env.VITE_API_BASE ?? "").replace(/\/+$/, "");

function makeUrl(path: string) {
  return `${API_BASE}${path.startsWith("/") ? path : `/${path}`}`;
}

// Build headers as a real Headers instance (type-safe)
function buildHeaders(init?: HeadersInit): Headers {
  const h = new Headers(init);
  h.set("Content-Type", "application/json");
  const token = getIdToken();            // should return "" if absent
  if (token) h.set("Authorization", `Bearer ${token}`);
  return h;
}

async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
  signal?: AbortSignal
): Promise<T> {
  const res = await fetch(makeUrl(path), {
    ...init,
    signal,
    headers: buildHeaders(init.headers),
  });
  if (res.status === 401 || res.status === 403) {
    location.assign("/login");
    throw new Error(`Unauthorized (${res.status})`);
  }
  if (!res.ok) {
    const txt = await res.text().catch(() => res.statusText);
    throw new Error(`${res.status} ${txt}`);
  }
  return res.json() as Promise<T>;
}

export function getHealth(signal?: AbortSignal): Promise<HealthResponse> {
  return apiFetch<HealthResponse>("/health", {}, signal);
}

export function getHoldings(
  opts?: { refresh?: boolean; signal?: AbortSignal }
): Promise<HoldingsResponse> {
  const refresh = opts?.refresh ? "?refresh=1" : "";
  return apiFetch<HoldingsResponse>(`/holdings${refresh}`, {}, opts?.signal);
}
