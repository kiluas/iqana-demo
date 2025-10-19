// apps/web/src/App.tsx
import React from "react";
import { Badge } from "./components/Badge";
import { HoldingsTable } from "./components/HoldingsTable";
import { getHealth, getHoldings } from "./api/client";
import type { HoldingsResponse } from "./types";
import { isAuthed, logout } from "./auth/auth";

function fmtEpoch(epochSec: number): string {
  try {
    return new Date(epochSec * 1000).toLocaleString();
  } catch {
    return `${epochSec}`;
  }
}

export const App: React.FC = () => {
  const [health, setHealth] = React.useState<string>("checking…");
  const [data, setData] = React.useState<HoldingsResponse | null>(null);
  const [loading, setLoading] = React.useState<boolean>(false);
  const [error, setError] = React.useState<string | null>(null);

  const load = React.useCallback(
    async (refresh = false, signal?: AbortSignal) => {
      setLoading(true);
      setError(null);
      try {
        // health in parallel (best-effort)
        getHealth(signal)
          .then((h) => setHealth(h.ok ? "ok" : "degraded"))
          .catch(() => setHealth("unknown"));

        const resp = await getHoldings({ refresh, signal });
        setData(resp);
      } catch (e: any) {
        const msg = e?.message || "Failed to load";
        setError(msg);
        // belt & suspenders: if the client didn't already redirect on 401/403
        if (/unauthor/i.test(msg) || /401|403/.test(msg)) {
          location.assign("/login");
        }
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  // initial fetch with clean abort on unmount
  React.useEffect(() => {
    const ac = new AbortController();
    void load(false, ac.signal);
    return () => ac.abort();
  }, [load]);

  return (
    <div className="mx-auto max-w-3xl p-6 sm:p-10 space-y-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">
          Iqana — Holdings
        </h1>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <span className="text-sm text-slate-500">API</span>
            <Badge color={health === "ok" ? "green" : "amber"}>{health}</Badge>
          </div>
          {isAuthed() && (
            <button
              onClick={() => logout()}
              className="rounded-xl bg-slate-200 px-3 py-1.5 text-slate-800 hover:bg-slate-300"
              title="Sign out"
            >
              Logout
            </button>
          )}
        </div>
      </header>

      <section className="flex items-center gap-2">
        <button
          onClick={() => void load(true)}
          disabled={loading}
          className="rounded-xl bg-slate-900 px-4 py-2 text-white shadow hover:bg-slate-800 active:bg-slate-700"
          title="Bypass cache and fetch fresh data"
        >
          {loading ? "Refreshing…" : "Refresh"}
        </button>
        {error && <span className="text-sm text-red-600">{error}</span>}
      </section>

      <section className="space-y-3">
        <div className="flex flex-wrap items-center gap-3">
          <Badge color="slate">
            {data ? (data.cached ? "cached" : "fresh") : "—"}
          </Badge>
          <Badge color="slate">
            fetched_at: {data ? fmtEpoch(data.fetched_at) : "—"}
          </Badge>
          <Badge color="slate">count: {data ? data.count : "—"}</Badge>
          <Badge color="slate">source: {data?.source ?? "—"}</Badge>
        </div>

        <HoldingsTable items={data?.items ?? []} />
      </section>

      <footer className="pt-8 text-center text-xs text-slate-500">
        using{" "}
        <code>
          VITE_API_BASE={import.meta.env.VITE_API_BASE ?? "(not set)"}
        </code>
      </footer>
    </div>
  );
};
