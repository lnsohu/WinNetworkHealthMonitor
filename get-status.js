// Netlify Function: Returns the latest status map collected by health-report
const store = global.__kioskStatusStore || {};

exports.handler = async function (event, context) {
  // Simple GET endpoint that returns the current in-memory store
  try {
    const result = Object.entries(store).map(([id, entry]) => ({
      id,
      receivedAt: entry.receivedAt,
      payload: entry.payload
    }));

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
