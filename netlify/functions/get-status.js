// Netlify Function: Returns the latest status from KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
  const store = getStore({
    name: "kiosk-status"
  });

  try {
    // List all entries in the store
    const entries = await store.list();
    const result = [];
    
    // Get each entry's data
    for (const key of entries) {
      const data = await store.get(key);
      if (data) {
        result.push({
          id: key,
          receivedAt: data.receivedAt,
          payload: data.payload
        });
      }
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ok: true, results: result })
    };
  } catch (err) {
    console.error('get-status error', err);
    return { statusCode: 500, body: 'Internal Server Error' };
  }
};

