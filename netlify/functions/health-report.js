// Netlify Function: Accepts POST from kiosks and stores last-seen status in KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
  console.log('Received request:', event.httpMethod);
  
  try {
    console.log('Creating KV Store with context:', context);
    const store = getStore({
      name: "kiosk-status",
      siteID: context.site.id
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

      const data = {
        receivedAt: now,
        payload: body
      };

      await store.set(id, JSON.stringify(data));
      console.log(`Stored status for ${id} at ${now}`);

      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ok: true, id, receivedAt: now })
      };
    } catch (err) {
      console.error('Failed to process POST:', err);
      return { 
        statusCode: 400, 
        body: JSON.stringify({ error: 'Bad Request', details: err.message }) 
      };
    }
  } catch (err) {
    console.error('Failed to initialize KV store:', err);
    return { 
      statusCode: 500, 
      body: JSON.stringify({ error: 'Internal Server Error', details: err.message }) 
    };
  }
};

