# Aha Moment Paywall Demo

A SwiftUI sample app demonstrating the "delayed paywall" pattern used by top subscription apps like Duolingo.

## The Pattern

**Don't show the paywall on first launch.** Instead:
1. Let users experience the core value first
2. Track when they hit their "aha moment" (completing a lesson, finishing a workout, etc.)
3. Show the paywall *after* they're hooked

## Implementation

This demo shows:
- RevenueCat SDK integration
- Event tracking for the "aha moment"
- Conditional paywall presentation
- Offering configuration

## Key Files

- `AhaMomentPaywallApp.swift` - App entry point
- `ContentView.swift` - Main UI with lesson completion
- `PaywallManager.swift` - RevenueCat integration & paywall logic
- `LessonView.swift` - Sample "lesson" that triggers the aha moment

## Setup

1. Add your RevenueCat API key to `PaywallManager.swift`
2. Configure your Offering in the RevenueCat dashboard
3. Run the app

## How It Works

```
User launches app
    ↓
Completes first lesson (aha moment)
    ↓
PaywallManager.trackAhaMoment() called
    ↓
Paywall presented with contextual copy
    ↓
User converts at 2-3x higher rate than cold paywall
```

## License

MIT - Use this in your own apps!
