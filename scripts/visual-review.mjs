import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const vite = path.join(root, 'node_modules', 'vite', 'bin', 'vite.js');
const port = process.env.PORT || '5199';

const server = spawn(process.execPath, [vite, '--host', '127.0.0.1', '--port', port, '--strictPort'], {
  cwd: root,
  stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: true,
});

let stdout = '';
let stderr = '';
server.stdout.on('data', (d) => {
  stdout += d;
  process.stdout.write(d);
});
server.stderr.on('data', (d) => {
  stderr += d;
  process.stderr.write(d);
});

function waitForServer() {
  return new Promise((resolve, reject) => {
    const startedAt = Date.now();
    const timer = setInterval(() => {
      if (stdout.includes('Local:') || stdout.includes('ready in')) {
        clearInterval(timer);
        resolve();
      } else if (Date.now() - startedAt > 30000) {
        clearInterval(timer);
        reject(new Error(`Vite did not start: ${stderr}`));
      }
    }, 300);
  });
}

async function main() {
  await waitForServer();
  await new Promise((resolve) => setTimeout(resolve, 1500));
  await import('./capture.mjs');
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => {
    server.kill();
  });
