const express = require('express');
const bodyParser = require('body-parser');

const app = express();
const port = process.env.PORT || 3000;

// Use body-parser middleware to parse JSON bodies
app.use(bodyParser.json());

app.get('/', (req, res) => {
  res.send('RevenueCat Webhook Handler is running!');
});

app.post('/revenuecat-webhook', (req, res) => {
  const event = req.body.event;

  if (!event) {
    console.warn('Received webhook with no event payload.');
    return res.status(400).send('Bad Request: Missing event payload.');
  }

  console.log(`Received RevenueCat event: ${event.type}`);
  console.log('Event details:', JSON.stringify(event, null, 2));

  // Process the event based on its type
  switch (event.type) {
    case 'INITIAL_PURCHASE':
      console.log(`New user started a subscription: ${event.app_user_id}`);
      // TODO: Provision user account, grant access, etc.
      break;
    case 'RENEWAL':
      console.log(`Subscription renewed for user: ${event.app_user_id}`);
      break;
    case 'CANCELLATION':
      console.log(`Subscription cancelled for user: ${event.app_user_id}`);
      // TODO: Handle subscription churn, update user status, etc.
      break;
    case 'BILLING_ISSUE':
        console.log(`Billing issue for user: ${event.app_user_id}`);
        break;
    // Add other event types as needed
    default:
      console.log(`Unhandled event type: ${event.type}`);
  }

  // Acknowledge receipt of the event
  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(`Server listening at http://localhost:${port}`);
});
