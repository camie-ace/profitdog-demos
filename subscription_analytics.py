"""
Subscription Analytics Helper for RevenueCat
=============================================

A practical toolkit for analyzing subscription metrics using the RevenueCat API.
Helps you understand MRR, churn, trial conversions, and cohort performance.

Requirements:
    pip install requests pandas

Usage:
    from subscription_analytics import SubscriptionAnalytics
    
    analytics = SubscriptionAnalytics(api_key="your_secret_api_key")
    metrics = analytics.get_overview_metrics()
    print(f"Current MRR: ${metrics['mrr']:,.2f}")

Author: ProfitDog 🐕 (github.com/camie-ace/profitdog-demos)
"""

import requests
from datetime import datetime, timedelta
from typing import Optional, Dict, List, Any
from dataclasses import dataclass
from enum import Enum


class Period(Enum):
    """Time periods for analytics queries."""
    DAILY = "day"
    WEEKLY = "week"
    MONTHLY = "month"


@dataclass
class SubscriptionMetrics:
    """Container for key subscription metrics."""
    mrr: float
    active_subscribers: int
    active_trials: int
    trial_conversion_rate: float
    churn_rate: float
    revenue_last_30_days: float
    new_subscribers_last_30_days: int
    timestamp: datetime


class SubscriptionAnalytics:
    """
    Analytics helper for RevenueCat subscription data.
    
    Provides easy access to key metrics like MRR, churn, trial conversions,
    and cohort analysis using the RevenueCat REST API v2.
    """
    
    BASE_URL = "https://api.revenuecat.com/v2"
    
    def __init__(self, api_key: str, project_id: Optional[str] = None):
        """
        Initialize the analytics helper.
        
        Args:
            api_key: Your RevenueCat Secret API key (sk_...)
            project_id: Optional project ID (uses default if not specified)
        """
        self.api_key = api_key
        self.project_id = project_id
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        })
    
    def _get(self, endpoint: str, params: Optional[Dict] = None) -> Dict[str, Any]:
        """Make a GET request to the RevenueCat API."""
        url = f"{self.BASE_URL}{endpoint}"
        response = self.session.get(url, params=params)
        response.raise_for_status()
        return response.json()
    
    def get_overview_metrics(self) -> SubscriptionMetrics:
        """
        Get a snapshot of key subscription metrics.
        
        Returns:
            SubscriptionMetrics with current MRR, subscriber counts, etc.
        
        Example:
            >>> metrics = analytics.get_overview_metrics()
            >>> print(f"MRR: ${metrics.mrr:,.2f}")
            >>> print(f"Active subscribers: {metrics.active_subscribers:,}")
        """
        # Fetch overview data from RevenueCat
        overview = self._get("/projects/overview")
        
        return SubscriptionMetrics(
            mrr=overview.get("mrr", 0.0),
            active_subscribers=overview.get("active_subscribers", 0),
            active_trials=overview.get("active_trials", 0),
            trial_conversion_rate=overview.get("trial_conversion_rate", 0.0),
            churn_rate=overview.get("churn_rate", 0.0),
            revenue_last_30_days=overview.get("revenue_30d", 0.0),
            new_subscribers_last_30_days=overview.get("new_subscribers_30d", 0),
            timestamp=datetime.utcnow(),
        )
    
    def get_mrr_history(
        self, 
        days: int = 30, 
        period: Period = Period.DAILY
    ) -> List[Dict[str, Any]]:
        """
        Get MRR history over a time period.
        
        Args:
            days: Number of days to look back
            period: Granularity (daily, weekly, monthly)
        
        Returns:
            List of dicts with 'date' and 'mrr' keys
        
        Example:
            >>> history = analytics.get_mrr_history(days=90)
            >>> for point in history[-7:]:  # Last week
            ...     print(f"{point['date']}: ${point['mrr']:,.2f}")
        """
        start_date = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
        end_date = datetime.utcnow().strftime("%Y-%m-%d")
        
        data = self._get("/metrics/mrr", params={
            "start_date": start_date,
            "end_date": end_date,
            "resolution": period.value,
        })
        
        return [
            {"date": point["date"], "mrr": point["value"]}
            for point in data.get("data_points", [])
        ]
    
    def get_churn_analysis(self, days: int = 30) -> Dict[str, Any]:
        """
        Analyze churn patterns over a time period.
        
        Args:
            days: Number of days to analyze
        
        Returns:
            Dict with churn rate, reasons breakdown, and trends
        
        Example:
            >>> churn = analytics.get_churn_analysis(days=30)
            >>> print(f"Churn rate: {churn['rate']:.1%}")
            >>> for reason, count in churn['reasons'].items():
            ...     print(f"  {reason}: {count}")
        """
        start_date = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
        
        data = self._get("/metrics/churn", params={
            "start_date": start_date,
        })
        
        return {
            "rate": data.get("churn_rate", 0.0),
            "churned_subscribers": data.get("churned_count", 0),
            "reasons": data.get("cancellation_reasons", {}),
            "voluntary_churn": data.get("voluntary_churn_rate", 0.0),
            "involuntary_churn": data.get("involuntary_churn_rate", 0.0),
        }
    
    def get_trial_conversion_funnel(self, days: int = 30) -> Dict[str, Any]:
        """
        Analyze trial-to-paid conversion funnel.
        
        Args:
            days: Number of days to analyze
        
        Returns:
            Dict with funnel stages and conversion rates
        
        Example:
            >>> funnel = analytics.get_trial_conversion_funnel()
            >>> print(f"Trial starts: {funnel['trial_starts']:,}")
            >>> print(f"Conversions: {funnel['conversions']:,}")
            >>> print(f"Conversion rate: {funnel['conversion_rate']:.1%}")
        """
        start_date = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
        
        data = self._get("/metrics/trials", params={
            "start_date": start_date,
        })
        
        trial_starts = data.get("trial_starts", 0)
        conversions = data.get("trial_conversions", 0)
        
        return {
            "trial_starts": trial_starts,
            "active_trials": data.get("active_trials", 0),
            "conversions": conversions,
            "conversion_rate": conversions / trial_starts if trial_starts > 0 else 0.0,
            "avg_trial_length_days": data.get("avg_trial_length", 0),
            "by_product": data.get("by_product", {}),
        }
    
    def get_revenue_by_product(self, days: int = 30) -> List[Dict[str, Any]]:
        """
        Break down revenue by product/entitlement.
        
        Args:
            days: Number of days to analyze
        
        Returns:
            List of products with revenue and subscriber counts
        
        Example:
            >>> products = analytics.get_revenue_by_product()
            >>> for p in products:
            ...     print(f"{p['name']}: ${p['revenue']:,.2f} ({p['subscribers']} subs)")
        """
        start_date = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
        
        data = self._get("/metrics/revenue/products", params={
            "start_date": start_date,
        })
        
        return [
            {
                "product_id": p["product_id"],
                "name": p.get("display_name", p["product_id"]),
                "revenue": p["revenue"],
                "subscribers": p["active_subscribers"],
                "mrr_contribution": p.get("mrr", 0.0),
            }
            for p in data.get("products", [])
        ]
    
    def get_cohort_retention(
        self, 
        cohort_month: Optional[str] = None,
        months_to_track: int = 6
    ) -> Dict[str, Any]:
        """
        Get retention data for a subscriber cohort.
        
        Args:
            cohort_month: Month to analyze (YYYY-MM format), defaults to 6 months ago
            months_to_track: Number of months to track retention
        
        Returns:
            Dict with cohort size and monthly retention percentages
        
        Example:
            >>> cohort = analytics.get_cohort_retention("2024-01")
            >>> print(f"Cohort size: {cohort['initial_size']:,}")
            >>> for month, rate in enumerate(cohort['retention']):
            ...     print(f"Month {month}: {rate:.1%}")
        """
        if cohort_month is None:
            cohort_date = datetime.utcnow() - timedelta(days=180)
            cohort_month = cohort_date.strftime("%Y-%m")
        
        data = self._get("/metrics/cohorts", params={
            "cohort_month": cohort_month,
            "periods": months_to_track,
        })
        
        return {
            "cohort_month": cohort_month,
            "initial_size": data.get("initial_subscribers", 0),
            "retention": data.get("retention_rates", []),
            "revenue_retention": data.get("revenue_retention_rates", []),
        }
    
    def calculate_ltv(self, arpu: Optional[float] = None) -> Dict[str, float]:
        """
        Calculate estimated customer lifetime value.
        
        Args:
            arpu: Average revenue per user (monthly). If not provided, 
                  calculates from current MRR and subscriber count.
        
        Returns:
            Dict with LTV estimates using different methods
        
        Example:
            >>> ltv = analytics.calculate_ltv()
            >>> print(f"Simple LTV: ${ltv['simple']:,.2f}")
            >>> print(f"Discounted LTV: ${ltv['discounted']:,.2f}")
        """
        metrics = self.get_overview_metrics()
        
        if arpu is None:
            arpu = (
                metrics.mrr / metrics.active_subscribers 
                if metrics.active_subscribers > 0 
                else 0.0
            )
        
        monthly_churn = metrics.churn_rate / 100 if metrics.churn_rate > 1 else metrics.churn_rate
        
        # Avoid division by zero
        if monthly_churn <= 0:
            monthly_churn = 0.05  # Assume 5% if no data
        
        # Simple LTV = ARPU / Churn Rate
        simple_ltv = arpu / monthly_churn
        
        # Discounted LTV (assuming 10% annual discount rate)
        monthly_discount = 0.10 / 12
        discounted_ltv = arpu / (monthly_churn + monthly_discount)
        
        # Average customer lifespan in months
        avg_lifespan = 1 / monthly_churn
        
        return {
            "arpu": arpu,
            "monthly_churn": monthly_churn,
            "simple": simple_ltv,
            "discounted": discounted_ltv,
            "avg_lifespan_months": avg_lifespan,
        }
    
    def generate_summary_report(self) -> str:
        """
        Generate a human-readable summary report.
        
        Returns:
            Formatted string with key metrics
        
        Example:
            >>> print(analytics.generate_summary_report())
        """
        metrics = self.get_overview_metrics()
        churn = self.get_churn_analysis()
        funnel = self.get_trial_conversion_funnel()
        ltv = self.calculate_ltv()
        
        report = f"""
📊 Subscription Analytics Summary
Generated: {metrics.timestamp.strftime('%Y-%m-%d %H:%M UTC')}

💰 REVENUE
   MRR: ${metrics.mrr:,.2f}
   Revenue (30d): ${metrics.revenue_last_30_days:,.2f}
   Estimated LTV: ${ltv['simple']:,.2f}

👥 SUBSCRIBERS
   Active: {metrics.active_subscribers:,}
   New (30d): {metrics.new_subscribers_last_30_days:,}
   Active Trials: {metrics.active_trials:,}

📈 GROWTH METRICS
   Trial Conversion: {funnel['conversion_rate']:.1%}
   Monthly Churn: {churn['rate']:.1%}
     - Voluntary: {churn['voluntary_churn']:.1%}
     - Involuntary: {churn['involuntary_churn']:.1%}

🎯 HEALTH INDICATORS
   ARPU: ${ltv['arpu']:,.2f}/month
   Avg Customer Lifespan: {ltv['avg_lifespan_months']:.1f} months
"""
        return report.strip()


# --- Convenience functions for quick analysis ---

def quick_health_check(api_key: str) -> Dict[str, Any]:
    """
    Quick health check of your subscription business.
    
    Args:
        api_key: Your RevenueCat Secret API key
    
    Returns:
        Dict with health status and key concerns
    
    Example:
        >>> health = quick_health_check("sk_...")
        >>> if health['concerns']:
        ...     print("⚠️ Issues found:")
        ...     for concern in health['concerns']:
        ...         print(f"  - {concern}")
    """
    analytics = SubscriptionAnalytics(api_key)
    metrics = analytics.get_overview_metrics()
    churn = analytics.get_churn_analysis()
    funnel = analytics.get_trial_conversion_funnel()
    
    concerns = []
    
    # Check for high churn
    if churn['rate'] > 0.10:
        concerns.append(f"High churn rate ({churn['rate']:.1%}) - industry avg is ~5-7%")
    
    # Check for low trial conversion
    if funnel['conversion_rate'] < 0.20:
        concerns.append(f"Low trial conversion ({funnel['conversion_rate']:.1%}) - aim for 25%+")
    
    # Check involuntary churn
    if churn['involuntary_churn'] > churn['voluntary_churn']:
        concerns.append("Involuntary churn exceeds voluntary - check payment recovery")
    
    status = "healthy" if not concerns else "needs_attention"
    
    return {
        "status": status,
        "mrr": metrics.mrr,
        "active_subscribers": metrics.active_subscribers,
        "churn_rate": churn['rate'],
        "trial_conversion": funnel['conversion_rate'],
        "concerns": concerns,
    }


# --- Example usage ---

if __name__ == "__main__":
    # Replace with your actual API key
    API_KEY = "sk_your_secret_api_key_here"
    
    print("🐕 ProfitDog Subscription Analytics Demo\n")
    
    # Note: This will fail with the placeholder key
    # Replace API_KEY with your real RevenueCat secret key to test
    
    try:
        analytics = SubscriptionAnalytics(API_KEY)
        
        # Generate full report
        print(analytics.generate_summary_report())
        
        # Quick health check
        print("\n" + "="*50)
        health = quick_health_check(API_KEY)
        print(f"\n🏥 Health Status: {health['status'].upper()}")
        if health['concerns']:
            print("Concerns:")
            for concern in health['concerns']:
                print(f"  ⚠️  {concern}")
        else:
            print("✅ No major concerns detected!")
            
    except Exception as e:
        print(f"Demo requires a valid RevenueCat API key.")
        print(f"Get yours at: https://app.revenuecat.com/settings/api-keys")
        print(f"\nError: {e}")
