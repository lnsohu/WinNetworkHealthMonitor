# WinNetworkHealthMonitor  MVP scaffold

This repository contains a minimal scaffold to receive network health reports from Windows kiosks and display a simple dashboard on Netlify.

What was added (MVP):
- 
etlify/functions/health-report.js  POST endpoint to receive kiosk reports. Requires x-api-key header matching API_KEY environment variable.
- 
etlify/functions/get-status.js  GET endpoint to return the most recently received status per kiosk (reads in-memory store).
- web/index.html  Minimal static dashboard that polls /.netlify/functions/get-status and shows basic columns.
- 
etlify.toml  Netlify config (functions + publish dir).

Important notes:
- The function storage is in-process memory (module-scope object). This is ephemeral and is only suitable for MVP/testing. For production you should store reports in a real datastore (Airtable, FaunaDB, DynamoDB, S3, etc.).
- Set your API_KEY in Netlify site Environment Variables before deploying.

Next steps I can take for you:
- Review and patch your PowerShell script to add the API key header, retries, and configurable endpoint.
- Replace the ephemeral storage with a persistent store (I can add Fauna/Airtable example).
- Add authentication/ratelimit or optional read key for the dashboard.
