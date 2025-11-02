// Netlify Function: Accepts POST from kiosks and stores last-seen status in memory (MVP)
// Note: This uses in-process memory to hold the latest status per kiosk. It's ephemeral
// and will be lost when the function container is recycled. For production, use a DB.

const kioskStore = global.__kioskStatusStore || {};
global.__kioskStatusStore = kioskStore;

exports.handler = async function (event, context) {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method Not Allowed' };
  }

  const apiKey = process.env.API_KEY || 'change-me';
  const headerKey = (event.headers['x-api-key'] || event.headers['X-Api-Key'] || event.headers['authorization'] || '').replace(/^Bearer\s+/i, '');

  if (!apiKey || headerKey !== apiKey) {
    return { statusCode: 401, body: 'Unauthorized' };
  }

  try {
    const body = JSON.parse(event.body || '{}');
    const id = body.Device || body.DeviceId || body.DeviceID || body.kioskId || 'unknown';
    const now = new Date().toISOString();

    kioskStore[id] = {
      receivedAt: now,
      payload: body
    };

    console.log(Stored status for  at );

    return {
      statusCode: 200,
      body: JSON.stringify({ ok: true, id, receivedAt: now })
    };
  } catch (err) {
    console.error('health-report error', err);
    return { statusCode: 400, body: 'Bad Request' };
  }
};
