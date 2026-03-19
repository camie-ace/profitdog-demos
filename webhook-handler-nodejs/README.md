# RevenueCat Webhook Handler (Node.js Example)

This directory contains a simple Node.js and Express server for receiving and processing webhooks from RevenueCat.

## What it does

This server provides a single endpoint, `/revenuecat-webhook`, that listens for `POST` requests from RevenueCat. When an event is received, it logs the event type and its payload to the console.

This is a basic template to get you started. You can extend it to:

-   Grant or revoke access to features in your app.
-   Send emails or notifications based on subscription events.
-   Sync subscription status with your own user database.
-   Analyze subscription data for analytics.

## How to Run

1.  **Install dependencies:**
    ```bash
    npm install
    ```

2.  **Start the server:**
    ```bash
    npm start
    ```

The server will start on port 3000 by default.

## Configure in RevenueCat

1.  To send events to your local server, you'll need to expose it to the internet. Tools like [ngrok](https://ngrok.com/) are great for this during development.
2.  In your RevenueCat project settings, go to "Webhooks" and add the public URL for your server's `/revenuecat-webhook` endpoint.
3.  RevenueCat will now send events to your server as they happen.
