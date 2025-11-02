// Netlify Function: Accepts POST from kiosks and stores last-seen status in memory (MVP)
// Note: This uses in-process memory to hold the latest status per kiosk. It's ephemeral
// and will be lost when the function container is recycled. For production, use a DB.

const kioskStore = global.__kioskStatusStore || {};
global.__kioskStatusStore = kioskStore;

exports.handler = async function (event, context) {
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

    kioskStore[id] = {
      receivedAt: now,
      payload: body
    };

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

