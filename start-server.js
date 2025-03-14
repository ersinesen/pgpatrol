// Setup a simple Express server to serve the Flutter web app
// and proxy API requests to our existing server.js
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const path = require('path');
const { exec } = require('child_process');
const cors = require('cors');

const app = express();

// Enable CORS for API requests
app.use(cors());

console.log('Starting web server and API server...');

// We'll start the API server after we ensure the port is available
let apiServer;

// Function to start the API server
function startApiServer() {
  console.log('Starting the actual server now...');
  apiServer = exec('node server.js');

  // Log stdout and stderr from API server
  apiServer.stdout.on('data', (data) => {
    console.log(data.toString().trim());
  });

  apiServer.stderr.on('data', (data) => {
    console.error(data.toString().trim());
  });
}

// Proxy API requests to our server.js
app.use('/api', createProxyMiddleware({
  target: 'http://localhost:3001',
  changeOrigin: true,
  pathRewrite: { '^/api': '' },
  onProxyReq: (proxyReq, req, res) => {
    // Make sure request body is forwarded 
    if (req.body) {
      const bodyData = JSON.stringify(req.body);
      proxyReq.setHeader('Content-Type', 'application/json');
      proxyReq.setHeader('Content-Length', Buffer.byteLength(bodyData));
      proxyReq.write(bodyData);
    }
  },
}));

// Serve the Flutter web app from the 'build/web' directory
app.use(express.static(path.join(__dirname, 'build/web')));

// Serve Flutter's main.dart.js file with the correct mime type
app.get('/*.js', (req, res, next) => {
  res.set('Content-Type', 'application/javascript');
  next();
});

// Handle all other routes by serving the Flutter index.html
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'build/web', 'index.html'));
});

// Start the web server
const PORT = process.env.PORT || 5000;
app.listen(PORT, '0.0.0.0', () => {
  console.log('Web server started');
  console.log(`Listening on port ${PORT}`);
  console.log(`Server running at: http://0.0.0.0:${PORT}`);
  console.log(`You can access the app in your browser at: https://${process.env.REPL_SLUG}.${process.env.REPL_OWNER}.repl.co`);
  
  // Start the API server after the web server is running
  startApiServer();
});

// Handle process termination
process.on('SIGINT', () => {
  console.log('Shutting down...');
  apiServer.kill();
  process.exit();
});

process.on('SIGTERM', () => {
  console.log('Shutting down...');
  apiServer.kill();
  process.exit();
});