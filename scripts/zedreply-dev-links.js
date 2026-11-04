const { spawn } = require('node:child_process');

const dashboardUrl = 'http://localhost:9000/';
const customerChatUrl = 'http://localhost:9000/zedreply-customer-test.html';
const readinessUrl = customerChatUrl;
const startupTimeoutMs = 20 * 60 * 1000;
const retryIntervalMs = 5000;
const printOnly = process.argv.includes('--print-only');
const waitOnly = process.argv.includes('--wait');

function printLinks() {
  console.log('AnansiFlow dashboard: http://localhost:9000/');
  console.log('Sample customer test chat: http://localhost:9000/zedreply-customer-test.html');
  console.log('For a company-specific chat, sign in and open Settings > Inboxes > that website inbox > Open live test chat.');
}

if (printOnly) {
  printLinks();
  process.exit(0);
}

async function waitForDashboard() {
  const deadline = Date.now() + startupTimeoutMs;
  let nextStatusAt = Date.now();

  while (Date.now() < deadline) {
    try {
      const response = await fetch(readinessUrl, { signal: AbortSignal.timeout(30000) });
      if (response.ok) return;
    } catch {
      // Rails is still booting or Docker has not published the port yet.
    }

    if (Date.now() >= nextStatusAt) {
      console.log('Waiting for the AnansiFlow dashboard to finish starting...');
      nextStatusAt = Date.now() + 30000;
    }

    await new Promise(resolve => setTimeout(resolve, retryIntervalMs));
  }

  throw new Error('AnansiFlow did not respond within 20 minutes. Check the Rails container logs.');
}

function openDashboard() {
  const command = process.platform === 'win32' ? 'cmd.exe' : process.platform === 'darwin' ? 'open' : 'xdg-open';
  const args = process.platform === 'win32' ? ['/c', 'start', '', dashboardUrl] : [dashboardUrl];
  spawn(command, args, { detached: true, stdio: 'ignore', windowsHide: true }).unref();
}

if (!waitOnly) printLinks();

waitForDashboard()
  .then(() => {
    console.log('Dashboard is ready. Opening the AnansiFlow homepage.');
    openDashboard();
    process.exit(0);
  })
  .catch(error => {
    console.error(error.message);
    process.exit(1);
  });
