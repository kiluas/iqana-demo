export type HoldingItem = {
  currency: string;
  balance: number;
};

export type HoldingsResponse = {
  cached: boolean;
  source: string;
  fetched_at: number; // epoch seconds
  count: number;
  items: HoldingItem[];
};

export type HealthResponse = {
  ok: boolean;
  name: string;
  time: number;
};
