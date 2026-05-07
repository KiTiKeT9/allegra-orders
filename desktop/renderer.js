const { ipcRenderer } = require('electron');

let orders = [];
let searchQuery = '';
let activeOrderIds = new Set();
let isInitialLoad = true;

document.addEventListener('DOMContentLoaded', async () => {
    // Tabs
    document.querySelectorAll('.nav-item').forEach(btn => {
        btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });

    // Search
    const searchInput = document.getElementById('searchInput');
    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            searchQuery = e.target.value.toLowerCase();
            renderOrders();
        });
    }

    // Server logs listener
    ipcRenderer.on('server-log', (event, line) => appendLog(line));

    // Показываем спиннер сразу
    renderLoadingState();

    // Ждём сервер
    const serverReady = await waitForServer();
    if (serverReady) {
        await loadOrders();
        setInterval(loadOrders, 15000);
    }
    await updateServerInfo();

    // Set app version
    ipcRenderer.invoke('get-app-version').then((version) => {
        const versionEls = ['appVersion', 'appVersionDisplay'];
        versionEls.forEach(id => {
            const el = document.getElementById(id);
            if (el) el.textContent = `v${version}`;
        });
    });

    // Update notifications
    ipcRenderer.on('update-checking', () => {
        showToast('Проверка обновлений...', 'info');
    });
    ipcRenderer.on('update-available', (event, version) => {
        showUpdateBanner(version, false);
    });
    ipcRenderer.on('update-not-available', () => {
        showToast('У вас актуальная версия', 'success');
    });
    ipcRenderer.on('update-progress', (event, percent) => {
        showUpdateBanner(null, false, percent);
    });
    ipcRenderer.on('update-downloaded', (event, version) => {
        showUpdateBanner(version, true);
    });
    ipcRenderer.on('update-error', (event, message) => {
        showToast(message, 'error');
    });
});

function switchTab(tab) {
    document.querySelectorAll('.nav-item').forEach(b => b.classList.remove('active'));
    document.querySelector(`.nav-item[data-tab="${tab}"]`).classList.add('active');

    document.querySelectorAll('.tab-panel').forEach(p => {
        p.classList.remove('active');
        p.style.display = 'none';
    });

    const panel = document.getElementById(`tab-${tab}`);
    panel.style.display = 'flex';
    panel.offsetHeight; // force reflow
    panel.classList.add('active');

    if (tab === 'server') updateServerInfo();
}

/* ORDERS */

function renderLoadingState() {
    const container = document.getElementById('ordersContainer');
    if (!container) return;
    container.innerHTML = `
        <div class="loading-wrap">
            <div class="spinner" style="width:40px;height:40px;border-width:3px;margin-bottom:16px"></div>
            <div style="font-weight:600;color:var(--text-muted)">Запуск сервера...</div>
            <div style="font-size:13px;color:var(--text-dim);margin-top:4px">Подождите, идёт инициализация</div>
        </div>`;
}

async function waitForServer() {
    for (let i = 0; i < 60; i++) {
        const ok = await ipcRenderer.invoke('check-server');
        if (ok.success) return true;
        await new Promise(r => setTimeout(r, 500));
    }
    const container = document.getElementById('ordersContainer');
    if (container) {
        container.innerHTML = `
            <div class="loading-wrap">
                <span class="material-icons" style="font-size:48px;color:var(--status-red);margin-bottom:12px">error_outline</span>
                <div style="font-weight:600">Сервер не запустился</div>
                <div style="font-size:13px;color:var(--text-dim);margin-top:4px">Проверьте вкладку «Сервер»</div>
            </div>`;
    }
    return false;
}

async function loadOrders() {
    const icon = document.getElementById('refreshIcon');
    if (icon) icon.classList.add('spinning');
    try {
        const newOrders = await ipcRenderer.invoke('get-orders');
        if (JSON.stringify(newOrders) === JSON.stringify(orders) && !isInitialLoad) return;
        orders = newOrders;
        renderOrders();
        isInitialLoad = false;
    } catch (e) {
        console.error('loadOrders error:', e);
    } finally {
        if (icon) setTimeout(() => icon.classList.remove('spinning'), 500);
    }
}

function renderOrders() {
    const container = document.getElementById('ordersContainer');
    if (!container) return;

    // Не перерисовываем, если пользователь редактирует поле
    if (document.activeElement && document.activeElement.classList.contains('detail-input')) return;

    let filtered = orders.filter(o => {
        const num = o.order_number.toLowerCase();
        const date = new Date(o.created_at).toLocaleString().toLowerCase();
        return num.includes(searchQuery) || date.includes(searchQuery);
    });
    filtered.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

    if (filtered.length === 0) {
        container.innerHTML = `
            <div class="loading-wrap">
                <div style="font-size:3rem;margin-bottom:1rem">🔎</div>
                <h3 style="margin:0 0 8px">${searchQuery ? 'Ничего не найдено' : 'Заказов нет'}</h3>
                <p style="color:var(--text-dim);margin:0">${searchQuery ? 'Попробуйте изменить запрос' : 'Отсканируйте QR-код через мобильное приложение'}</p>
            </div>`;
        return;
    }

    const html = filtered.map((o, i) => {
        const isActive = activeOrderIds.has(o.order_number);
        const date = new Date(o.created_at).toLocaleString();
        return `
        <div class="order-card ${isActive ? 'active' : ''}" id="card-${o.order_number}" style="animation-delay:${isInitialLoad ? i * 0.04 : 0}s">
            <div class="order-summary" onclick="window.toggleOrder('${o.order_number}')">
                <div class="order-main-info">
                    <div class="order-icon">📦</div>
                    <div>
                        <div style="font-weight:700;font-size:1.1rem">${o.order_number}</div>
                        <div style="color:var(--text-muted);font-size:0.82rem">Создан: ${date}</div>
                    </div>
                </div>
                <div class="order-stats">
                    <div class="stat-badge"><span class="stat-label">Всего</span><span class="stat-value">${o.total_count}</span></div>
                    <div class="stat-badge"><span class="stat-label">Разбито</span><span class="stat-value" style="color:var(--status-red)">${o.damaged || 0}</span></div>
                    <div class="stat-badge"><span class="stat-label">Проблемы</span><span class="stat-value" style="color:var(--status-yellow)">${o.issues || 0}</span></div>
                    <span class="material-icons expand-icon">expand_more</span>
                </div>
            </div>
            <div class="order-details">
                <div class="details-content">
                    <div class="details-grid">
                        <div class="detail-input-group"><label>Всего</label><input type="number" class="detail-input" id="total-${o.order_number}" value="${o.total_count}"></div>
                        <div class="detail-input-group"><label>Разбито</label><input type="number" class="detail-input" id="dam-${o.order_number}" value="${o.damaged || 0}"></div>
                        <div class="detail-input-group"><label>Проблемы</label><input type="number" class="detail-input" id="iss-${o.order_number}" value="${o.issues || 0}"></div>
                    </div>
                    <div class="action-bar">
                        <button class="btn btn-danger" onclick="window.deleteOrder('${o.order_number}')"><span class="material-icons" style="font-size:18px">delete_outline</span>Удалить</button>
                        <button class="btn btn-info" onclick="window.openFolder('${o.order_number}')"><span class="material-icons" style="font-size:18px">folder_open</span>Папка</button>
                        <button class="btn btn-primary" onclick="window.saveOrder('${o.order_number}')"><span class="material-icons" style="font-size:18px">save</span>Сохранить</button>
                    </div>
                </div>
            </div>
        </div>`;
    }).join('');

    container.innerHTML = html;
}

window.toggleOrder = (id) => {
    const card = document.getElementById(`card-${id}`);
    if (!card) return;
    if (card.classList.contains('active')) {
        card.classList.remove('active');
        activeOrderIds.delete(id);
    } else {
        card.classList.add('active');
        activeOrderIds.add(id);
    }
};

window.saveOrder = async (id) => {
    const btn = event.currentTarget;
    const orig = btn.innerHTML;
    btn.innerHTML = '<div class="spinner"></div>';
    btn.disabled = true;
    const data = {
        orderNumber: id,
        total_count: parseInt(document.getElementById(`total-${id}`).value) || 0,
        damaged: parseInt(document.getElementById(`dam-${id}`).value) || 0,
        issues: parseInt(document.getElementById(`iss-${id}`).value) || 0
    };
    try {
        await ipcRenderer.invoke('update-order', data);
        btn.style.background = 'var(--status-green)';
        btn.innerHTML = '<span class="material-icons">check</span>';
        const idx = orders.findIndex(o => o.order_number === id);
        if (idx !== -1) orders[idx] = { ...orders[idx], ...data };
        setTimeout(loadOrders, 800);
    } catch (e) {
        btn.innerHTML = orig;
        btn.disabled = false;
        btn.style.background = '';
        alert('Ошибка при сохранении');
    }
};

window.deleteOrder = async (id) => {
    if (confirm(`Удалить заказ ${id}?`)) {
        await ipcRenderer.invoke('delete-order', id);
        activeOrderIds.delete(id);
        await loadOrders();
    }
};

window.openFolder = async (id) => {
    const res = await ipcRenderer.invoke('open-order-folder', id);
    if (!res.success) alert('Ошибка: ' + res.error);
};

window.refreshData = loadOrders;

/* SERVER */

async function updateServerInfo() {
    const status = await ipcRenderer.invoke('server-status');
    const dataDir = document.getElementById('dataDirText');
    const addrContainer = document.getElementById('serverAddresses');
    if (dataDir) dataDir.innerText = status.dataDir || '—';
    if (addrContainer) {
        if (status.addresses && status.addresses.length > 0) {
            addrContainer.innerHTML = status.addresses.map(url =>
                `<span class="server-status-value mono" style="font-size:13px">${url}</span>`
            ).join('');
        } else {
            addrContainer.innerHTML = '<span class="server-status-value mono">http://localhost:' + (status.port || '8000') + '</span>';
        }
    }
    const term = document.getElementById('serverLogs');
    if (term && term.children.length === 0 && status.logs) {
        status.logs.forEach(l => appendLog(l));
    }
}

window.clearServerLogs = async () => {
    await ipcRenderer.invoke('clear-logs');
    document.getElementById('serverLogs').innerHTML = '';
};

window.checkForUpdates = async () => {
    const btn = event.currentTarget;
    const orig = btn.innerHTML;
    btn.innerHTML = '<div class="spinner" style="width:16px;height:16px;border-width:2px"></div>';
    btn.disabled = true;
    try {
        await ipcRenderer.invoke('check-for-updates');
    } finally {
        btn.innerHTML = orig;
        btn.disabled = false;
    }
};

window.selectDataFolder = async () => {
    const res = await ipcRenderer.invoke('select-data-folder');
    if (res.success) {
        const el = document.getElementById('dataDirText');
        if (el) el.innerText = res.path;
        alert('Папка данных изменена! Перезапустите приложение.');
    }
};

function appendLog(line) {
    const term = document.getElementById('serverLogs');
    if (!term) return;
    const div = document.createElement('div');
    div.className = `log-line ${line.type}`;
    div.innerHTML = `<span class="log-time">${line.time}</span> <span class="log-text">${escapeHtml(line.text)}</span>`;
    term.appendChild(div);
    term.scrollTop = term.scrollHeight;
}

function escapeHtml(t) {
    const d = document.createElement('div');
    d.innerText = t;
    return d.innerHTML;
}

/* UPDATE NOTIFICATIONS */

function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `
        <span class="material-icons">${type === 'success' ? 'check_circle' : type === 'error' ? 'error' : 'info'}</span>
        <span>${message}</span>
    `;
    document.body.appendChild(toast);
    setTimeout(() => toast.classList.add('show'), 10);
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

function showUpdateBanner(version, isDownloaded, progress = null) {
    let banner = document.getElementById('update-banner');

    if (!banner) {
        banner = document.createElement('div');
        banner.id = 'update-banner';
        banner.className = 'update-banner';
        document.body.appendChild(banner);
    }

    let content = '';

    if (isDownloaded) {
        content = `
            <div class="update-banner-content">
                <span class="material-icons update-icon">system_update</span>
                <span class="update-text">Доступна новая версия ${version}. Перезапустить?</span>
                <button class="btn btn-primary btn-sm" id="update-restart-btn">
                    <span class="material-icons" style="font-size:16px">restart_alt</span>
                    Перезапустить
                </button>
                <button class="btn btn-ghost btn-sm" id="update-later-btn">Позже</button>
            </div>`;
    } else if (progress !== null) {
        content = `
            <div class="update-banner-content">
                <span class="material-icons update-icon">system_update</span>
                <span class="update-text">Загрузка обновления: ${progress}%</span>
                <div class="update-progress-bar">
                    <div class="update-progress-fill" style="width:${progress}%"></div>
                </div>
            </div>`;
    } else {
        content = `
            <div class="update-banner-content">
                <span class="material-icons update-icon">system_update</span>
                <span class="update-text">Доступна новая версия ${version}</span>
                <div class="spinner" style="width:20px;height:20px;border-width:2px"></div>
            </div>`;
    }

    banner.innerHTML = content;

    document.body.appendChild(banner);

    if (isDownloaded) {
        document.getElementById('update-restart-btn').addEventListener('click', async () => {
            await ipcRenderer.invoke('quit-and-install');
        });
        document.getElementById('update-later-btn').addEventListener('click', () => {
            banner.remove();
        });
    }
}
