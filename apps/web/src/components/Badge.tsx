import React from "react";

export const Badge: React.FC<{
  color?: "green" | "amber" | "slate";
  children: React.ReactNode;
}> = ({ color = "slate", children }) => {
  const map = {
    green: "bg-green-100 text-green-800 ring-green-200",
    amber: "bg-amber-100 text-amber-800 ring-amber-200",
    slate: "bg-slate-100 text-slate-800 ring-slate-200",
  } as const;
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-sm ring-1 ${map[color]}`}
    >
      {children}
    </span>
  );
};
