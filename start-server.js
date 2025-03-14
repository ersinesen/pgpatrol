// This script starts the server and ensures port detection works in Replit
const express = require('express');
const { spawn } = require('child_process');

// First create a simple server that Replit can detect
const tempApp = express();
const tempPort = 5000;

// Create a temporary server just to help Replit detect the port
const tempServer = tempApp.listen(tempPort, '0.0.0.0', () => {
  console.log(`Opening port ${tempPort} for Replit to detect...`);
  
  // Close the temporary server after Replit has a chance to detect it
  setTimeout(() => {
    tempServer.close(() => {
      console.log('Starting the actual server now...');
      
      // Start the real server
      const server = spawn('node', ['server.js'], { 
        stdio: 'inherit'  // Pass all stdio to parent process
      });
  
      server.on('error', (err) => {
        console.error('Failed to start server:', err);
        process.exit(1);
      });
    });
  }, 2000);
});