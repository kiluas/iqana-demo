import React from "react";
import type { HoldingItem } from "../types";

type Props = {
  items: HoldingItem[];
};

export const HoldingsTable: React.FC<Props> = ({ items }) => {
  if (!items.length) {
    return (
      <div className="rounded-xl border border-slate-200 bg-white p-6 text-slate-500">
        No holdings to display.
      </div>
    );
  }
  return (
    <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white">
      <table className="min-w-full text-left text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th className="px-4 py-3 font-semibold text-slate-700">Currency</th>
            <th className="px-4 py-3 font-semibold text-slate-700">Balance</th>
          </tr>
        </thead>
        <tbody>
          {items.map((it) => (
            <tr key={it.currency} className="border-t border-slate-100">
              <td className="px-4 py-3">{it.currency}</td>
              <td className="px-4 py-3 tabular-nums">{it.balance}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
