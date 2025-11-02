// Netlify Function: Accepts POST from kiosks and stores last-seen status in KV Store
const { getStore } = require("@netlify/blobs");

exports.handler = async function (event, context) {
  const store = getStore({
    name: "kiosk-status"
  });
  // Allow GET to return the in-memory store (ephemeral). POST to store updates.
  if (event.httpMethod === 'GET') {
    // Temporarily disabled API key check for testing
    return {
      statusCode: 200,
      body: JSON.stringify({ ok: true, store: kioskStore })
    };
  }

  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method Not Allowed' };
  }

  // Temporarily disabled API key check for testing
  try {
    const body = JSON.parse(event.body || '{}');
    const id = body.Device || body.DeviceId || body.DeviceID || body.kioskId || 'unknown';
    const now = new Date().toISOString();

    const data = {
      receivedAt: now,
      payload: body
    };

    await store.set(id, data);
    console.log(`Stored status for ${id} at ${now}`);

    return {
      statusCode: 200,
      body: JSON.stringify({ ok: true, id, receivedAt: now })
    };
  } catch (err) {
    console.error('health-report error', err);
    return { statusCode: 400, body: 'Bad Request' };
  }
};

