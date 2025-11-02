// Netlify Function: Returns the latest status from KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
  console.log('Received status request');
  
  try {
    const store = getStore({
      name: "kiosk-status"
    });
    console.log('KV Store initialized');

    const entries = await store.list();
    console.log('Found entries:', entries);
    
    const result = [];
    for (const key of entries) {
      const data = await store.get(key);
      if (data) {
        try {
          const parsedData = JSON.parse(data);
          result.push({
            id: key,
            ...parsedData
          });
        } catch (parseErr) {
          console.error(`Failed to parse data for ${key}:`, parseErr);
        }
      }
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ok: true, results: result })
    };
  } catch (err) {
    console.error('Failed to retrieve status:', err);
    return { 
      statusCode: 500, 
      body: JSON.stringify({ error: 'Internal Server Error', details: err.message }) 
    };
  }
};

