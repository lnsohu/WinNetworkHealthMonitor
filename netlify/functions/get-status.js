// Netlify Function: Returns the latest status from KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
    console.log('Received status request');
    console.log('Environment:', {
      SITE_ID: process.env.SITE_ID,
      NETLIFY_API_TOKEN: process.env.NETLIFY_API_TOKEN ? '(set)' : '(not set)',
      NODE_ENV: process.env.NODE_ENV
    });
  
  try {
    // Note: In production, these values are automatically provided by Netlify
    const storeConfig = {
      name: "kiosk-status",
      token: process.env.NETLIFY_API_TOKEN, // Always include the token
      siteID: process.env.SITE_ID || context.site?.id || "winnetworkhealthmonitor"
    };
    
    console.log('Store config:', { ...storeConfig, token: storeConfig.token ? '(set)' : '(not set)' });
    const store = getStore(storeConfig);
    console.log('KV Store initialized');    const entries = await store.listKeys();
    console.log('Found entries:', entries);
    
    const result = [];
    for (const key of entries) {
      const data = await store.get(key);
      if (data) {
        const parsedData = JSON.parse(await data.text());
        result.push({
          id: key,
          ...parsedData
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

