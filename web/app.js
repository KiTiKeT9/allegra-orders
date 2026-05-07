(function() {
    'use strict';

    // ====== STATE ======
    window.API_URL = location.origin + '/api';
    window.html5QrCode = null;
    window.currentOrder = null;
    window.selectedFiles = [];
    window.boxCount = 1;
    window._scannerInitialized = false;

    // ====== DOM READY ======
    document.addEventListener('DOMContentLoaded', function() {
        initScanner();
        bindEvents();
        checkHealth();
        setInterval(checkHealth, 5000);
        window.updateUploadButton();
    });

    // ====== EVENT BINDING ======
    function bindEvents() {
        document.getElementById('btnManualTop').addEventListener('click', window.manualInput);
        document.getElementById('btnManualBottom').addEventListener('click', window.manualInput);
        document.getElementById('btnBack').addEventListener('click', window.showScanner);
        document.getElementById('btnMinus').addEventListener('click', function() { window.changeCount(-1); });
        document.getElementById('btnPlus').addEventListener('click', function() { window.changeCount(1); });
        document.getElementById('boxCount').addEventListener('change', function() {
            window.boxCount = Math.max(1, parseInt(this.value) || 1);
            this.value = window.boxCount;
            window.updateUploadButton();
        });
        document.getElementById('btnClear').addEventListener('click', window.clearFiles);
        document.getElementById('uploadBtn').addEventListener('click', window.uploadFiles);
        document.getElementById('photoInput').addEventListener('change', window.handleFileSelect);
        document.getElementById('videoInput').addEventListener('change', window.handleFileSelect);
    }

    // ====== SCANNER ======
    window.initScanner = function() {
        var reader = document.getElementById('reader');
        var overlay = document.getElementById('scannerOverlay');
        if (!reader) return;

        // Очищаем
        if (window.html5QrCode) {
            try { window.html5QrCode.stop(); } catch(e) {}
            window.html5QrCode.clear();
            window.html5QrCode = null;
        }

        // Сбрасываем DOM reader
        reader.innerHTML = '';
        if (overlay) overlay.style.display = 'flex';

        // Проверка безопасности
        if (!window.isSecureContext && location.hostname !== 'localhost' && location.hostname !== '127.0.0.1') {
            showCameraError('Камера требует HTTPS.<br>Используйте кнопку «Ввести вручную».');
            return;
        }

        // Создаём сканер
        try {
            window.html5QrCode = new Html5Qrcode('reader', { verbose: false });
        } catch(e) {
            showCameraError('Библиотека сканера не загружена.<br>Проверьте интернет.');
            return;
        }

        var config = {
            fps: 10,
            qrbox: { width: 220, height: 220 },
            aspectRatio: 1.0,
            disableFlip: false
        };

        window.html5QrCode.start(
            { facingMode: 'environment' },
            config,
            window.onScanSuccess,
            window.onScanFailure
        ).then(function() {
            window._scannerInitialized = true;
            console.log('[Scanner] Camera started');
        }).catch(function(err) {
            console.error('[Scanner] Start failed:', err);
            showCameraError(
                (err && err.message ? err.message : 'Не удалось запустить камеру') +
                '<br><span style="font-size:12px;color:#64748B">Разрешите доступ в настройках Safari</span>'
            );
        });
    };

    function showCameraError(html) {
        var reader = document.getElementById('reader');
        var overlay = document.getElementById('scannerOverlay');
        if (overlay) overlay.style.display = 'none';
        if (reader) {
            reader.innerHTML = '<div class="camera-fallback">' +
                '<span class="material-icons" style="font-size:48px;color:#F59E0B">no_photography</span>' +
                '<p>Камера недоступна</p>' +
                '<p class="hint">' + html + '</p>' +
            '</div>';
        }
    }

    window.onScanSuccess = function(decodedText) {
        if (!decodedText) return;
        console.log('[Scanner] Detected:', decodedText);

        if (navigator.vibrate) navigator.vibrate(80);

        // Останавливаем камеру
        if (window.html5QrCode) {
            window.html5QrCode.stop().catch(function(){});
        }

        window.showUploadScreen(decodedText);
    };

    window.onScanFailure = function(error) {
        // Игнорируем ошибки декодирования кадров — это нормально
    };

    window.manualInput = function() {
        var val = prompt('Введите номер заказа:');
        if (val && val.trim()) {
            window.showUploadScreen(val.trim());
        }
    };

    // ====== SCREEN TRANSITIONS ======
    window.showUploadScreen = function(orderNumber) {
        window.currentOrder = orderNumber;
        var scanner = document.getElementById('scannerScreen');
        var upload = document.getElementById('uploadScreen');
        var display = document.getElementById('orderNumberDisplay');
        if (display) display.innerText = orderNumber;

        if (scanner) scanner.classList.add('slide-out-left');
        if (upload) upload.classList.add('slide-in-right', 'active');

        setTimeout(function() {
            if (scanner) scanner.classList.remove('active', 'slide-out-left');
            if (upload) upload.classList.remove('slide-in-right');
        }, 350);
    };

    window.showScanner = function() {
        var scanner = document.getElementById('scannerScreen');
        var upload = document.getElementById('uploadScreen');

        window.resetUploadForm();

        if (upload) upload.classList.add('slide-out-right');
        if (scanner) scanner.classList.add('slide-in-left', 'active');

        setTimeout(function() {
            if (upload) upload.classList.remove('active', 'slide-out-right');
            if (scanner) scanner.classList.remove('slide-in-left');
            window.initScanner();
        }, 350);
    };

    // ====== UPLOAD LOGIC ======
    window.changeCount = function(val) {
        window.boxCount = Math.max(1, window.boxCount + val);
        var input = document.getElementById('boxCount');
        if (input) input.value = window.boxCount;
        window.updateUploadButton();
    };

    window.handleFileSelect = function(e) {
        var files = Array.from(e.target.files);
        files.forEach(function(file) {
            window.selectedFiles.push(file);
            window.renderPreview(file);
        });
        e.target.value = '';
        window.updateFileCount();
        window.updateUploadButton();
    };

    window.renderPreview = function(file) {
        var grid = document.getElementById('fileGrid');
        if (!grid) return;
        var div = document.createElement('div');
        div.className = 'preview-item';

        if (file.type && file.type.startsWith('video/')) {
            div.innerHTML = '<div class="video-thumb">' +
                '<span class="material-icons" style="color:#6366F1;font-size:32px">videocam</span>' +
                '<span class="video-label">VIDEO</span>' +
            '</div>';
        } else {
            var reader = new FileReader();
            reader.onload = function(ev) { div.style.backgroundImage = 'url(' + ev.target.result + ')'; };
            reader.readAsDataURL(file);
        }

        var removeBtn = document.createElement('div');
        removeBtn.className = 'remove-btn';
        removeBtn.innerHTML = '<span class="material-icons">close</span>';
        removeBtn.addEventListener('click', function(ev) {
            ev.stopPropagation();
            var idx = window.selectedFiles.findIndex(function(f) { return f.name === file.name && f.size === file.size; });
            if (idx > -1) window.selectedFiles.splice(idx, 1);
            div.remove();
            window.updateFileCount();
            window.updateUploadButton();
        });

        div.appendChild(removeBtn);
        grid.appendChild(div);
    };

    window.updateFileCount = function() {
        var el = document.getElementById('fileCount');
        if (el) el.innerText = '(' + window.selectedFiles.length + ')';
    };

    window.updateUploadButton = function() {
        var btn = document.getElementById('uploadBtn');
        var text = document.getElementById('uploadText');
        if (!btn || !text) return;
        if (window.selectedFiles.length === 0) {
            btn.disabled = true;
            text.innerText = 'Выберите файлы';
        } else {
            btn.disabled = false;
            text.innerText = 'Отправить ' + window.boxCount + ' шт.';
        }
    };

    window.clearFiles = function() {
        window.selectedFiles = [];
        var grid = document.getElementById('fileGrid');
        if (grid) {
            grid.querySelectorAll('.preview-item').forEach(function(p) { p.remove(); });
        }
        window.updateFileCount();
        window.updateUploadButton();
    };

    window.uploadFiles = function() {
        if (window.selectedFiles.length === 0) {
            alert('Выберите файлы для отправки!');
            return;
        }

        var btn = document.getElementById('uploadBtn');
        var text = document.getElementById('uploadText');
        btn.disabled = true;
        var originalText = text.innerText;
        text.innerText = 'Отправка...';
        btn.classList.add('loading');

        var formData = new FormData();
        formData.append('order_number', window.currentOrder);
        formData.append('count', window.boxCount);
        window.selectedFiles.forEach(function(file) { formData.append('files', file); });

        fetch(window.API_URL + '/upload', { method: 'POST', body: formData })
        .then(function(response) {
            if (response.ok) {
                alert('Заказ ' + window.currentOrder + ' успешно отправлен!');
                window.showScanner();
            } else {
                return response.json().catch(function() { return {}; });
            }
        })
        .then(function(err) {
            if (err && err.detail) alert('Ошибка сервера: ' + err.detail);
        })
        .catch(function(e) {
            alert('Ошибка сети. Убедитесь, что сервер запущен.');
        })
        .finally(function() {
            btn.disabled = false;
            text.innerText = originalText;
            btn.classList.remove('loading');
        });
    };

    window.resetUploadForm = function() {
        window.selectedFiles = [];
        window.boxCount = 1;
        window.currentOrder = null;
        var input = document.getElementById('boxCount');
        if (input) input.value = 1;
        var grid = document.getElementById('fileGrid');
        if (grid) grid.querySelectorAll('.preview-item').forEach(function(p) { p.remove(); });
        window.updateFileCount();
        window.updateUploadButton();
    };

    // ====== HEALTH ======
    window.checkHealth = function() {
        fetch(window.API_URL + '/health', { cache: 'no-store' })
        .then(function(res) {
            var dot = document.getElementById('serverStatus');
            if (dot) dot.classList.toggle('online', res.ok);
        })
        .catch(function() {
            var dot = document.getElementById('serverStatus');
            if (dot) dot.classList.remove('online');
        });
    };

})();
