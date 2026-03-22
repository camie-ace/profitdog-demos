# React Analytics Dashboard

A ready-to-use React dashboard for visualizing RevenueCat subscription metrics.

## Features

- **Real-time metrics**: MRR, subscribers, churn rate, trial conversion
- **Interactive charts**: MRR trend, churn breakdown, trial funnel, revenue by product
- **Auto-refresh**: Configurable polling interval
- **Loading states**: Skeleton UI while fetching
- **Error handling**: Retry functionality on failures
- **TypeScript**: Full type safety

## Installation

```bash
npm install recharts date-fns
# or
yarn add recharts date-fns
```

## Quick Start

```tsx
import { SubscriptionDashboard, RevenueCatProvider } from './SubscriptionDashboard';

function App() {
  return (
    <RevenueCatProvider 
      apiKey={process.env.REACT_APP_RC_API_KEY!}
      baseUrl="/api/revenuecat" // Your backend proxy
    >
      <SubscriptionDashboard />
    </RevenueCatProvider>
  );
}
```

## ⚠️ Important: Backend Proxy

**Never expose your RevenueCat secret API key in client-side code.**

Create a backend route that proxies requests to RevenueCat's API:

```ts
// Express example
router.get('/api/revenuecat/overview', async (req, res) => {
  const response = await fetch(
    `https://api.revenuecat.com/v2/projects/${PROJECT_ID}/metrics/overview`,
    { headers: { Authorization: `Bearer ${SECRET_API_KEY}` } }
  );
  res.json(await response.json());
});
```

## Using the Hook Directly

```tsx
import { useSubscriptionAnalytics } from './SubscriptionDashboard';

function CustomMetrics() {
  const { metrics, loading, error } = useSubscriptionAnalytics({
    startDate: subDays(new Date(), 7), // Last 7 days
    refreshInterval: 60000, // Refresh every minute
  });

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error.message}</div>;

  return (
    <div>
      <p>MRR: ${metrics?.mrr.toLocaleString()}</p>
      <p>Subscribers: {metrics?.activeSubscribers}</p>
    </div>
  );
}
```

## Metrics Available

| Metric | Description |
|--------|-------------|
| `mrr` | Monthly Recurring Revenue |
| `mrrChange` | MRR change percentage |
| `activeSubscribers` | Current paying subscribers |
| `activeTrials` | Users currently in trial |
| `churnRate` | Monthly churn percentage |
| `ltv` | Customer lifetime value |
| `conversionRate` | Trial-to-paid conversion rate |

## Customizing Charts

The component uses [Recharts](https://recharts.org/) for visualization. Modify the chart components in `SubscriptionDashboard.tsx` to match your brand:

```tsx
<Line
  stroke="#your-brand-color"
  strokeWidth={2}
  // ...
/>
```

## Styling

Uses Tailwind CSS classes. Adapt to your CSS framework or replace with styled-components/CSS modules as needed.

---

Built by ProfitDog 🐕 | [More demos](https://github.com/camie-ace/profitdog-demos)
