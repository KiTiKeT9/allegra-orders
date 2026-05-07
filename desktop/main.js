const { app, BrowserWindow, ipcMain, shell, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const http = require('http');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const net = require('net');

let mainWindow;
let serverInstance = null;
let currentPort = 8000;
let serverAddresses = [];
const serverLogs = [];
const MAX_LOGS = 500;
const CONFIG_FILE = 'app-config.json';

let CONFIG = {
  dataDir: path.join(app.getPath('userData'), 'data')
};

function loadConfig() {
  try {
    const p = path.join(app.getPath('userData'), CONFIG_FILE);
    if (fs.existsSync(p)) {
      const saved = JSON.parse(fs.readFileSync(p, 'utf-8'));
      if (saved.dataDir && fs.existsSync(saved.dataDir)) CONFIG.dataDir = saved.dataDir;
    }
  } catch (e) {}
}

function saveConfig() {
  try {
    const p = path.join(app.getPath('userData'), CONFIG_FILE);
    fs.writeFileSync(p, JSON.stringify(CONFIG, null, 2), 'utf-8');
  } catch (e) {}
}

function getPaths() {
  return {
    dataDir: CONFIG.dataDir,
    uploadDir: path.join(CONFIG.dataDir, 'orders'),
    metadataFile: path.join(CONFIG.dataDir, 'metadata.json')
  };
}

function ensureDataDirs() {
  const { dataDir, uploadDir } = getPaths();
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });
  if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
}

function pushLog(text, type = 'info') {
  const line = { time: new Date().toLocaleTimeString(), text: String(text).trim(), type };
  serverLogs.push(line);
  if (serverLogs.length > MAX_LOGS) serverLogs.shift();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('server-log', line);
  }
}

function loadMetadata() {
  try {
    const { metadataFile } = getPaths();
    if (fs.existsSync(metadataFile)) return JSON.parse(fs.readFileSync(metadataFile, 'utf-8'));
  } catch (e) { pushLog('Error reading metadata.json: ' + e.message, 'error'); }
  return {};
}

function saveMetadata(metadata) {
  try {
    const { metadataFile } = getPaths();
    fs.writeFileSync(metadataFile, JSON.stringify(metadata, null, 2), 'utf-8');
  } catch (e) { pushLog('Error writing metadata.json: ' + e.message, 'error'); }
}

function isPortFree(port) {
  return new Promise((resolve) => {
    const tester = net.createServer()
      .once('error', () => resolve(false))
      .once('listening', () => {
        tester.close();
        resolve(true);
      })
      .listen(port, '127.0.0.1');
  });
}

async function findFreePort(startPort) {
  for (let p = startPort; p < startPort + 100; p++) {
    if (await isPortFree(p)) return p;
  }
  return 0;
}

async function startInternalServer() {
  if (serverInstance) return;
  ensureDataDirs();
  const { uploadDir } = getPaths();

  currentPort = await findFreePort(8000);
  pushLog(`Selected port: ${currentPort}`, 'info');

  const expressApp = express();
  expressApp.use(cors());
  expressApp.use(express.urlencoded({ extended: true }));
  expressApp.use(express.json());

  expressApp.use((req, res, next) => {
    pushLog(`${req.method} ${req.url}`, 'info');
    next();
  });

  // Storage with window support: orders/ORDER_NUMBER/window_X/
  const storage = multer.diskStorage({
    destination: (req, file, cb) => {
      const orderNumber = req.body.order_number || 'unknown';
      const windowNumber = req.body.window_number || '1';
      const windowDir = path.join(uploadDir, orderNumber, `window_${windowNumber}`);
      if (!fs.existsSync(windowDir)) fs.mkdirSync(windowDir, { recursive: true });
      cb(null, windowDir);
    },
    filename: (req, file, cb) => cb(null, file.originalname)
  });
  const upload = multer({ storage });

  expressApp.post('/api/upload', upload.array('files'), (req, res) => {
    try {
      const orderNumber = req.body.order_number;
      let count = parseInt(req.body.count);
      if (isNaN(count)) count = 1;
      const windowNumber = req.body.window_number || '1';
      const appendMode = req.body.append_mode === 'true';
      
      if (!orderNumber) return res.status(400).json({ detail: 'order_number required' });

      const uploadedFiles = (req.files || []).map(f => f.originalname);
      const metadata = loadMetadata();
      const timestamp = new Date().toISOString();

      // Count total files across all windows
      const orderDir = path.join(uploadDir, orderNumber);
      let totalFilesCount = 0;
      if (fs.existsSync(orderDir)) {
        const windows = fs.readdirSync(orderDir).filter(f => f.startsWith('window_'));
        for (const w of windows) {
          const wPath = path.join(orderDir, w);
          if (fs.statSync(wPath).isDirectory()) {
            totalFilesCount += fs.readdirSync(wPath).length;
          }
        }
      }

      if (metadata[orderNumber]) {
        // Existing order
        if (appendMode) {
          metadata[orderNumber].total_count += count;
        } else {
          metadata[orderNumber].total_count += count;
        }
        metadata[orderNumber].files_count = totalFilesCount;
        metadata[orderNumber].files.push(...uploadedFiles.map(f => `window_${windowNumber}/${f}`));
        metadata[orderNumber].updated_at = timestamp;
      } else {
        // New order
        metadata[orderNumber] = {
          order_number: orderNumber,
          created_at: timestamp,
          updated_at: timestamp,
          total_count: count,
          delivered: 0,
          in_transit: 0,
          damaged: 0,
          issues: 0,
          notes: '',
          files: uploadedFiles.map(f => `window_${windowNumber}/${f}`),
          files_count: totalFilesCount
        };
      }
      saveMetadata(metadata);
      res.json({ success: true, window: windowNumber, total_files: totalFilesCount });
    } catch (e) {
      pushLog('Upload error: ' + e.message, 'error');
      res.status(500).json({ detail: e.message });
    }
  });

  // Check if order exists
  expressApp.get('/api/check-order/:order_number', (req, res) => {
    const metadata = loadMetadata();
    const orderNumber = req.params.order_number;
    const exists = !!metadata[orderNumber];
    let windows_count = 0;
    if (exists) {
      const orderDir = path.join(uploadDir, orderNumber);
      if (fs.existsSync(orderDir)) {
        const windows = fs.readdirSync(orderDir).filter(f => f.startsWith('window_'));
        windows_count = windows.length;
      }
      if (!windows_count) {
        windows_count = metadata[orderNumber].total_count || 0;
      }
    }
    res.json({ exists, windows_count });
  });

  expressApp.get('/api/orders', (req, res) => {
    const metadata = loadMetadata();
    const orders = Object.values(metadata).sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    res.json({ orders, total: orders.length });
  });

  expressApp.put('/api/orders/:order_number', (req, res) => {
    const metadata = loadMetadata();
    const id = req.params.order_number;
    if (!metadata[id]) return res.status(404).json({ detail: 'Order not found' });
    const order = metadata[id];
    order.total_count = parseInt(req.body.total_count) || 0;
    order.damaged = parseInt(req.body.damaged) || 0;
    order.issues = parseInt(req.body.issues) || 0;
    order.notes = req.body.notes || '';
    order.updated_at = new Date().toISOString();
    saveMetadata(metadata);
    res.json({ success: true });
  });

  expressApp.delete('/api/orders/:order_number', (req, res) => {
    const metadata = loadMetadata();
    const id = req.params.order_number;
    if (metadata[id]) {
      const orderDir = path.join(uploadDir, id);
      if (fs.existsSync(orderDir)) { try { fs.rmSync(orderDir, { recursive: true }); } catch (e) {} }
      delete metadata[id];
      saveMetadata(metadata);
    }
    res.json({ success: true });
  });

  expressApp.get('/api/health', (req, res) => {
    res.json({ status: 'ok', orders_count: Object.keys(loadMetadata()).length });
  });

  const webDir = path.join(__dirname, '..', 'web');
  if (fs.existsSync(webDir)) {
    expressApp.use('/', express.static(webDir));
    expressApp.get('*', (req, res) => {
      if (!req.path.startsWith('/api/')) {
        res.sendFile(path.join(webDir, 'index.html'));
      }
    });
    pushLog('Web interface connected', 'info');
  }

  const os = require('os');
  const interfaces = os.networkInterfaces();
  serverAddresses = [];
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) serverAddresses.push(iface.address);
    }
  }

  return new Promise((resolve) => {
    serverInstance = expressApp.listen(currentPort, '0.0.0.0', () => {
      pushLog(`Server running on port ${currentPort}`, 'info');
      pushLog(`Available at: ${serverAddresses.join(', ')}`, 'info');
      resolve();
    });

    serverInstance.on('error', (err) => {
      pushLog('Server error: ' + err.message, 'error');
      serverInstance = null;
      resolve();
    });
  });
}

function stopInternalServer() {
  if (serverInstance) {
    serverInstance.close();
    serverInstance = null;
    pushLog('Server stopped', 'warn');
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400, height: 850, minWidth: 900, minHeight: 600,
    webPreferences: { nodeIntegration: true, contextIsolation: false },
    title: 'Allegra Logistics', show: false
  });
  mainWindow.loadFile('index.html');
  mainWindow.once('ready-to-show', () => mainWindow.show());
  loadConfig();
  startInternalServer();
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { stopInternalServer(); if (process.platform !== 'darwin') app.quit(); });

// IPC
ipcMain.handle('get-orders', async () => Object.values(loadMetadata()).sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)));
ipcMain.handle('update-order', async (e,data)=>{
  const m=loadMetadata(); if(!m[data.orderNumber]) return {success:false,error:'Not found'};
  Object.assign(m[data.orderNumber],{total_count:data.total_count||0,damaged:data.damaged||0,issues:data.issues||0,updated_at:new Date().toISOString()});
  saveMetadata(m); return {success:true};
});
ipcMain.handle('delete-order', async (e,id)=>{
  const m=loadMetadata(); if(m[id]){ const d=path.join(getPaths().uploadDir,id); if(fs.existsSync(d)) try{fs.rmSync(d,{recursive:true})}catch(e){} delete m[id]; saveMetadata(m);}
  return {success:true};
});

ipcMain.handle('check-server', async () => {
  return new Promise((resolve) => {
    if (!serverInstance) return resolve({ success: false });
    const req = http.get(`http://127.0.0.1:${currentPort}/api/health`, (res) => {
      resolve({ success: res.statusCode === 200, port: currentPort });
    });
    req.on('error', () => resolve({ success: false }));
    req.setTimeout(2000, () => { req.destroy(); resolve({ success: false }); });
  });
});

ipcMain.handle('open-orders-folder', async ()=>{ ensureDataDirs(); shell.openPath(getPaths().uploadDir); return {success:true}; });
ipcMain.handle('open-order-folder', async (e,id)=>{
  const d=path.join(getPaths().uploadDir,id); if(!fs.existsSync(d)) fs.mkdirSync(d,{recursive:true}); shell.openPath(d); return {success:true};
});
ipcMain.handle('server-status', ()=>({
  running:!!serverInstance,
  url:`http://0.0.0.0:${currentPort}`,
  addresses: serverAddresses.map(ip => `http://${ip}:${currentPort}`),
  dataDir:CONFIG.dataDir,
  logs:serverLogs
}));
ipcMain.handle('clear-logs', ()=>{ serverLogs.length=0; return true; });

ipcMain.handle('select-data-folder', async ()=>{
  const result = await dialog.showOpenDialog(mainWindow, { properties: ['openDirectory'] });
  if (!result.canceled && result.filePaths.length > 0) {
    CONFIG.dataDir = result.filePaths[0];
    saveConfig();
    ensureDataDirs();
    pushLog('Data folder changed: ' + CONFIG.dataDir, 'info');
    return { success: true, path: CONFIG.dataDir };
  }
  return { success: false };
});
