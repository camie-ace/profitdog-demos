/**
 * React Subscription Analytics Dashboard
 * 
 * A client-side dashboard component for visualizing RevenueCat subscription metrics.
 * Uses RevenueCat's REST API to fetch and display key business metrics.
 * 
 * Prerequisites:
 * - RevenueCat project with API access
 * - npm install recharts date-fns
 * 
 * Usage:
 * ```tsx
 * import { SubscriptionDashboard, RevenueCatProvider } from './SubscriptionDashboard';
 * 
 * function App() {
 *   return (
 *     <RevenueCatProvider apiKey={process.env.REVENUECAT_API_KEY!}>
 *       <SubscriptionDashboard />
 *     </RevenueCatProvider>
 *   );
 * }
 * ```
 * 
 * Note: API calls should be proxied through your backend in production
 * to avoid exposing your secret API key.
 * 
 * @author ProfitDog 🐕
 */

import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useMemo,
  ReactNode,
} from 'react';
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  PieChart,
  Pie,
  Cell,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { format, subDays, parseISO } from 'date-fns';

// ============================================================================
// Types
// ============================================================================

interface MRRDataPoint {
  date: string;
  mrr: number;
  newMrr: number;
  churnedMrr: number;
  expansionMrr: number;
}

interface ChurnDataPoint {
  date: string;
  voluntaryChurn: number;
  involuntaryChurn: number;
  churnRate: number;
}

interface TrialConversion {
  date: string;
  trialsStarted: number;
  converted: number;
  conversionRate: number;
}

interface RevenueByProduct {
  productId: string;
  productName: string;
  revenue: number;
  subscribers: number;
  percentOfTotal: number;
}

interface DashboardMetrics {
  mrr: number;
  mrrChange: number;
  activeSubscribers: number;
  activeTrials: number;
  churnRate: number;
  ltv: number;
  conversionRate: number;
}

interface RevenueCatContextValue {
  apiKey: string;
  projectId?: string;
  baseUrl: string;
}

// ============================================================================
// Context & Provider
// ============================================================================

const RevenueCatContext = createContext<RevenueCatContextValue | null>(null);

interface ProviderProps {
  apiKey: string;
  projectId?: string;
  /** Override for backend proxy, defaults to RevenueCat API */
  baseUrl?: string;
  children: ReactNode;
}

export function RevenueCatProvider({
  apiKey,
  projectId,
  baseUrl = '/api/revenuecat', // Proxy through your backend!
  children,
}: ProviderProps) {
  const value = useMemo(
    () => ({ apiKey, projectId, baseUrl }),
    [apiKey, projectId, baseUrl]
  );
  return (
    <RevenueCatContext.Provider value={value}>
      {children}
    </RevenueCatContext.Provider>
  );
}

function useRevenueCatContext() {
  const ctx = useContext(RevenueCatContext);
  if (!ctx) {
    throw new Error('useRevenueCat* must be used within RevenueCatProvider');
  }
  return ctx;
}

// ============================================================================
// API Hook
// ============================================================================

interface UseAnalyticsOptions {
  startDate?: Date;
  endDate?: Date;
  refreshInterval?: number; // ms
}

interface AnalyticsData {
  metrics: DashboardMetrics | null;
  mrrHistory: MRRDataPoint[];
  churnHistory: ChurnDataPoint[];
  trialConversions: TrialConversion[];
  revenueByProduct: RevenueByProduct[];
  loading: boolean;
  error: Error | null;
  refresh: () => Promise<void>;
}

export function useSubscriptionAnalytics(
  options: UseAnalyticsOptions = {}
): AnalyticsData {
  const { baseUrl, apiKey } = useRevenueCatContext();
  const {
    startDate = subDays(new Date(), 30),
    endDate = new Date(),
    refreshInterval,
  } = options;

  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null);
  const [mrrHistory, setMrrHistory] = useState<MRRDataPoint[]>([]);
  const [churnHistory, setChurnHistory] = useState<ChurnDataPoint[]>([]);
  const [trialConversions, setTrialConversions] = useState<TrialConversion[]>([]);
  const [revenueByProduct, setRevenueByProduct] = useState<RevenueByProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);

    const headers = {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    };

    const formatDate = (d: Date) => format(d, 'yyyy-MM-dd');
    const start = formatDate(startDate);
    const end = formatDate(endDate);

    try {
      // Fetch all data in parallel
      const [overviewRes, mrrRes, churnRes, trialsRes, productsRes] =
        await Promise.all([
          fetch(`${baseUrl}/overview?start_date=${start}&end_date=${end}`, {
            headers,
          }),
          fetch(`${baseUrl}/mrr?start_date=${start}&end_date=${end}`, {
            headers,
          }),
          fetch(`${baseUrl}/churn?start_date=${start}&end_date=${end}`, {
            headers,
          }),
          fetch(`${baseUrl}/trials?start_date=${start}&end_date=${end}`, {
            headers,
          }),
          fetch(`${baseUrl}/products?start_date=${start}&end_date=${end}`, {
            headers,
          }),
        ]);

      // Parse responses
      const overview = await overviewRes.json();
      const mrr = await mrrRes.json();
      const churn = await churnRes.json();
      const trials = await trialsRes.json();
      const products = await productsRes.json();

      // Transform API responses to our types
      setMetrics({
        mrr: overview.mrr ?? 0,
        mrrChange: overview.mrr_change_percent ?? 0,
        activeSubscribers: overview.active_subscribers ?? 0,
        activeTrials: overview.active_trials ?? 0,
        churnRate: overview.churn_rate ?? 0,
        ltv: overview.ltv ?? 0,
        conversionRate: overview.trial_conversion_rate ?? 0,
      });

      setMrrHistory(
        (mrr.data ?? []).map((d: any) => ({
          date: d.date,
          mrr: d.mrr,
          newMrr: d.new_mrr ?? 0,
          churnedMrr: d.churned_mrr ?? 0,
          expansionMrr: d.expansion_mrr ?? 0,
        }))
      );

      setChurnHistory(
        (churn.data ?? []).map((d: any) => ({
          date: d.date,
          voluntaryChurn: d.voluntary ?? 0,
          involuntaryChurn: d.involuntary ?? 0,
          churnRate: d.rate ?? 0,
        }))
      );

      setTrialConversions(
        (trials.data ?? []).map((d: any) => ({
          date: d.date,
          trialsStarted: d.started ?? 0,
          converted: d.converted ?? 0,
          conversionRate: d.conversion_rate ?? 0,
        }))
      );

      const totalRevenue = (products.data ?? []).reduce(
        (sum: number, p: any) => sum + (p.revenue ?? 0),
        0
      );
      setRevenueByProduct(
        (products.data ?? []).map((p: any) => ({
          productId: p.product_id,
          productName: p.product_name ?? p.product_id,
          revenue: p.revenue ?? 0,
          subscribers: p.subscribers ?? 0,
          percentOfTotal:
            totalRevenue > 0 ? ((p.revenue ?? 0) / totalRevenue) * 100 : 0,
        }))
      );
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setLoading(false);
    }
  }, [baseUrl, apiKey, startDate, endDate]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  useEffect(() => {
    if (!refreshInterval) return;
    const id = setInterval(fetchData, refreshInterval);
    return () => clearInterval(id);
  }, [fetchData, refreshInterval]);

  return {
    metrics,
    mrrHistory,
    churnHistory,
    trialConversions,
    revenueByProduct,
    loading,
    error,
    refresh: fetchData,
  };
}

// ============================================================================
// Dashboard Components
// ============================================================================

const COLORS = ['#6366f1', '#22c55e', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4'];

interface MetricCardProps {
  title: string;
  value: string | number;
  change?: number;
  suffix?: string;
  loading?: boolean;
}

function MetricCard({ title, value, change, suffix, loading }: MetricCardProps) {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <h3 className="text-sm font-medium text-gray-500">{title}</h3>
      {loading ? (
        <div className="animate-pulse h-8 bg-gray-200 rounded mt-2" />
      ) : (
        <>
          <p className="text-2xl font-bold mt-2">
            {typeof value === 'number' ? value.toLocaleString() : value}
            {suffix && <span className="text-sm font-normal ml-1">{suffix}</span>}
          </p>
          {change !== undefined && (
            <p
              className={`text-sm mt-1 ${
                change >= 0 ? 'text-green-600' : 'text-red-600'
              }`}
            >
              {change >= 0 ? '↑' : '↓'} {Math.abs(change).toFixed(1)}%
            </p>
          )}
        </>
      )}
    </div>
  );
}

interface ChartCardProps {
  title: string;
  children: ReactNode;
  loading?: boolean;
}

function ChartCard({ title, children, loading }: ChartCardProps) {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <h3 className="text-lg font-semibold mb-4">{title}</h3>
      {loading ? (
        <div className="animate-pulse h-64 bg-gray-100 rounded" />
      ) : (
        <div className="h-64">{children}</div>
      )}
    </div>
  );
}

// ============================================================================
// Main Dashboard
// ============================================================================

export function SubscriptionDashboard() {
  const {
    metrics,
    mrrHistory,
    churnHistory,
    trialConversions,
    revenueByProduct,
    loading,
    error,
    refresh,
  } = useSubscriptionAnalytics({ refreshInterval: 5 * 60 * 1000 }); // 5 min refresh

  if (error) {
    return (
      <div className="p-6 bg-red-50 border border-red-200 rounded-lg">
        <h2 className="text-red-800 font-semibold">Failed to load analytics</h2>
        <p className="text-red-600 mt-1">{error.message}</p>
        <button
          onClick={refresh}
          className="mt-4 px-4 py-2 bg-red-100 text-red-800 rounded hover:bg-red-200"
        >
          Retry
        </button>
      </div>
    );
  }

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(val);

  return (
    <div className="p-6 bg-gray-50 min-h-screen">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Subscription Analytics</h1>
        <button
          onClick={refresh}
          disabled={loading}
          className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 disabled:opacity-50"
        >
          {loading ? 'Refreshing...' : 'Refresh'}
        </button>
      </div>

      {/* Key Metrics Row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <MetricCard
          title="Monthly Recurring Revenue"
          value={formatCurrency(metrics?.mrr ?? 0)}
          change={metrics?.mrrChange}
          loading={loading}
        />
        <MetricCard
          title="Active Subscribers"
          value={metrics?.activeSubscribers ?? 0}
          loading={loading}
        />
        <MetricCard
          title="Trial Conversion Rate"
          value={`${(metrics?.conversionRate ?? 0).toFixed(1)}%`}
          loading={loading}
        />
        <MetricCard
          title="Churn Rate"
          value={`${(metrics?.churnRate ?? 0).toFixed(2)}%`}
          loading={loading}
        />
      </div>

      {/* Charts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* MRR Trend */}
        <ChartCard title="MRR Trend" loading={loading}>
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={mrrHistory}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis
                dataKey="date"
                tickFormatter={(d) => format(parseISO(d), 'MMM d')}
              />
              <YAxis tickFormatter={(v) => `$${(v / 1000).toFixed(0)}k`} />
              <Tooltip
                formatter={(v: number) => formatCurrency(v)}
                labelFormatter={(d) => format(parseISO(d), 'MMM d, yyyy')}
              />
              <Legend />
              <Line
                type="monotone"
                dataKey="mrr"
                name="MRR"
                stroke="#6366f1"
                strokeWidth={2}
                dot={false}
              />
              <Line
                type="monotone"
                dataKey="newMrr"
                name="New"
                stroke="#22c55e"
                strokeWidth={1}
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Churn Breakdown */}
        <ChartCard title="Churn Breakdown" loading={loading}>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={churnHistory}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis
                dataKey="date"
                tickFormatter={(d) => format(parseISO(d), 'MMM d')}
              />
              <YAxis />
              <Tooltip
                labelFormatter={(d) => format(parseISO(d), 'MMM d, yyyy')}
              />
              <Legend />
              <Bar
                dataKey="voluntaryChurn"
                name="Voluntary"
                stackId="a"
                fill="#f59e0b"
              />
              <Bar
                dataKey="involuntaryChurn"
                name="Involuntary"
                stackId="a"
                fill="#ef4444"
              />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Trial Conversions */}
        <ChartCard title="Trial Conversions" loading={loading}>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={trialConversions}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis
                dataKey="date"
                tickFormatter={(d) => format(parseISO(d), 'MMM d')}
              />
              <YAxis yAxisId="left" />
              <YAxis
                yAxisId="right"
                orientation="right"
                tickFormatter={(v) => `${v}%`}
              />
              <Tooltip
                labelFormatter={(d) => format(parseISO(d), 'MMM d, yyyy')}
              />
              <Legend />
              <Bar
                yAxisId="left"
                dataKey="trialsStarted"
                name="Trials Started"
                fill="#6366f1"
              />
              <Bar
                yAxisId="left"
                dataKey="converted"
                name="Converted"
                fill="#22c55e"
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="conversionRate"
                name="Rate %"
                stroke="#f59e0b"
              />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Revenue by Product */}
        <ChartCard title="Revenue by Product" loading={loading}>
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={revenueByProduct}
                dataKey="revenue"
                nameKey="productName"
                cx="50%"
                cy="50%"
                outerRadius={80}
                label={({ name, percent }) =>
                  `${name} (${(percent * 100).toFixed(0)}%)`
                }
              >
                {revenueByProduct.map((_, index) => (
                  <Cell
                    key={`cell-${index}`}
                    fill={COLORS[index % COLORS.length]}
                  />
                ))}
              </Pie>
              <Tooltip formatter={(v: number) => formatCurrency(v)} />
            </PieChart>
          </ResponsiveContainer>
        </ChartCard>
      </div>

      {/* Secondary Metrics */}
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <MetricCard
          title="Active Trials"
          value={metrics?.activeTrials ?? 0}
          loading={loading}
        />
        <MetricCard
          title="Customer LTV"
          value={formatCurrency(metrics?.ltv ?? 0)}
          loading={loading}
        />
        <MetricCard
          title="Products"
          value={revenueByProduct.length}
          loading={loading}
        />
      </div>
    </div>
  );
}

// ============================================================================
// Backend Proxy Example (for reference)
// ============================================================================

/**
 * Example Express route to proxy RevenueCat API requests:
 * 
 * ```ts
 * // api/revenuecat.ts
 * import express from 'express';
 * 
 * const router = express.Router();
 * const RC_API_KEY = process.env.REVENUECAT_API_V2_KEY!;
 * const RC_PROJECT_ID = process.env.REVENUECAT_PROJECT_ID!;
 * 
 * router.get('/overview', async (req, res) => {
 *   const { start_date, end_date } = req.query;
 *   const response = await fetch(
 *     `https://api.revenuecat.com/v2/projects/${RC_PROJECT_ID}/metrics/overview?` +
 *     `start_date=${start_date}&end_date=${end_date}`,
 *     { headers: { Authorization: `Bearer ${RC_API_KEY}` } }
 *   );
 *   res.json(await response.json());
 * });
 * 
 * // Similar routes for /mrr, /churn, /trials, /products
 * ```
 */

export default SubscriptionDashboard;
