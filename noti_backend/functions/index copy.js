const express = require('express');
const fetch = require('node-fetch');
const app = express();
const port = 5000;

app.use(express.json());

// Your existing endpoints
app.get('/some-endpoint', (req, res) => {
    res.json({ message: 'This is an existing endpoint' });
});

// Add the /send-notification endpoint
app.post('/send-notification', async (req, res) => {
    try {
        const { token, title, body } = req.body;

        if (!token || !title || !body) {
            return res.status(400).json({ error: 'Missing parameters: token, title, and body are required' });
        }

        const FCM_SERVER_KEY = 'YOUR_FCM_SERVER_KEY';
        const fcmUrl = 'https://fcm.googleapis.com/fcm/send';
        const headers = {
            'Content-Type': 'application/json',
            'Authorization': `key=${FCM_SERVER_KEY}`,
        };
        const payload = {
            to: token,
            notification: {
                title: title,
                body: body,
            },
        };

        console.log('Sending notification to token:', token);
        console.log('Payload:', payload);

        const response = await fetch(fcmUrl, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify(payload),
        });

        const responseData = await response.json();
        console.log('FCM Response:', response.status, responseData);

        if (response.ok) {
            return res.status(200).json({ success: true, response: responseData });
        } else {
            return res.status(response.status).json({ error: 'Failed to send notification', details: responseData });
        }
    } catch (error) {
        console.error('Error sending notification:', error);
        return res.status(500).json({ error: 'Internal server error', details: error.message });
    }
});

app.listen(port, () => {
    console.log(`Server is running on http://localhost:${port}`);
});