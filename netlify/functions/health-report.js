// Netlify Function: Accepts POST from kiosks and stores last-seen status in KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
  console.log('Received request:', event.httpMethod);
  
  try {
    const store = getStore({
      name: "kiosk-status",
      token: process.env.NETLIFY_API_TOKEN
    });
    console.log('KV Store initialized');

    // Allow GET to return the current store state
    if (event.httpMethod === 'GET') {
      try {
        const entries = await store.list();
        const result = [];
        
        for (const key of entries) {
          const data = await store.get(key);
          if (data) {
            result.push({
              id: key,
              ...data
            });
          }
        }

        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ok: true, results: result })
        };
      } catch (err) {
        console.error('GET operation failed:', err);
        return { 
          statusCode: 500, 
          body: JSON.stringify({ error: 'Failed to retrieve data', details: err.message }) 
        };
      }
    }

    if (event.httpMethod !== 'POST') {
      return { statusCode: 405, body: 'Method Not Allowed' };
    }

    try {
      const body = JSON.parse(event.body || '{}');
      const id = body.Device || body.DeviceId || body.DeviceID || body.kioskId || 'unknown';
      const now = new Date().toISOString();

      await store.set(id, body);
      console.log(`Stored status for ${id} at ${now}`);

      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ok: true, id, receivedAt: now })
      };
    } catch (err) {
      console.error('Failed to process POST:', err);
      console.log('Error stack:', err.stack);
      return { 
        statusCode: 400, 
        body: JSON.stringify({ 
          error: 'Bad Request', 
          message: err.message,
          stack: err.stack 
        }) 
      };
    }
  } catch (err) {
    console.error('Failed to initialize or use KV store:', err);
    console.log('Error stack:', err.stack);
    return { 
      statusCode: 500, 
      body: JSON.stringify({ 
        error: 'Internal Server Error', 
        message: err.message,
        stack: err.stack
      }) 
    };
  }
};

