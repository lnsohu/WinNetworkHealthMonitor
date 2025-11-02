// Netlify Function: Returns the latest status from KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
  console.log('Received status request');
  
  try {
    // Note: In production, these values are automatically provided by Netlify
    const store = getStore({
      name: "kiosk-status",
      siteID: process.env.SITE_ID || "winnetworkhealthmonitor",
      token: process.env.NETLIFY_API_TOKEN
    });
    console.log('KV Store initialized');

    const entries = await store.list();
    console.log('Found entries:', entries);
    
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
    console.error('Failed to retrieve status:', err);
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

