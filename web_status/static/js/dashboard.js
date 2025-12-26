/**
 * Dashboard Beta - Simplified Interface with Advanced Toggles
 * Includes Status Dashboard + Sources Manager + Tab Switching + Advanced Mode
 */

// =============================================================================
// TAB SWITCHING LOGIC
// =============================================================================

let sourcesInitialized = false;

document.addEventListener('DOMContentLoaded', () => {
    // Initialize tab switching
    initTabSwitching();

    // Initialize advanced toggles
    initAdvancedToggles();

    // Initialize status tab (always loads first)
    initStatusDashboard();
});

// =============================================================================
// ADVANCED TOGGLE FUNCTIONALITY
// =============================================================================

function initAdvancedToggles() {
    // Status advanced toggle
    const statusAdvancedToggle = document.getElementById('status-advanced-toggle');
    const statusAdvancedSection = document.getElementById('status-advanced-section');
    if (statusAdvancedToggle && statusAdvancedSection) {
        statusAdvancedToggle.addEventListener('click', () => {
            statusAdvancedSection.classList.toggle('visible');
            statusAdvancedToggle.textContent = statusAdvancedSection.classList.contains('visible')
                ? '▾ Hide technical details'
                : '▸ Show technical details';
        });
    }

    // Logs advanced toggle
    const logsAdvancedToggle = document.getElementById('logs-advanced-toggle');
    const logsAdvancedSection = document.getElementById('logs-advanced-section');
    if (logsAdvancedToggle && logsAdvancedSection) {
        logsAdvancedToggle.addEventListener('click', () => {
            logsAdvancedSection.classList.toggle('visible');
            logsAdvancedToggle.textContent = logsAdvancedSection.classList.contains('visible')
                ? '▾ Hide logs'
                : '▸ Show logs';
        });
    }

    // Source switch advanced toggle
    const sourceSwitchToggle = document.getElementById('source-switch-advanced-toggle');
    const sourceSwitchSection = document.getElementById('source-switch-advanced-section');
    if (sourceSwitchToggle && sourceSwitchSection) {
        sourceSwitchToggle.addEventListener('click', () => {
            sourceSwitchSection.classList.toggle('visible');
            sourceSwitchToggle.textContent = sourceSwitchSection.classList.contains('visible')
                ? '▾ Hide technical details'
                : '▸ Show technical details';
        });
    }

    // Sources table advanced toggle (for future enhancement)
    const sourcesTableToggle = document.getElementById('sources-table-advanced-toggle');
    if (sourcesTableToggle) {
        sourcesTableToggle.addEventListener('click', () => {
            // Placeholder for showing technical columns (ID, full paths, etc.)
            alert('Advanced table view coming soon!');
        });
    }
}

function initTabSwitching() {
    document.querySelectorAll('.tab-button').forEach(button => {
        button.addEventListener('click', () => {
            const tabId = button.getAttribute('data-tab');
            switchTab(tabId);
        });
    });
}

function switchTab(tabId) {
    // Update tab buttons
    document.querySelectorAll('.tab-button').forEach(btn => {
        btn.classList.remove('active');
    });
    document.querySelector(`[data-tab="${tabId}"]`).classList.add('active');
    
    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
    });
    document.getElementById(`tab-${tabId}`).classList.add('active');
    
    // Initialize sources manager on first load
    if (tabId === 'sources' && !sourcesInitialized) {
        initSourcesManager();
        sourcesInitialized = true;
    }
}

// =============================================================================
// STATUS DASHBOARD FUNCTIONALITY (from dashboard.js)
// =============================================================================

function initStatusDashboard() {
    const bannerText = document.getElementById("banner-text");
    const bannerPill = document.getElementById("banner-pill");
    const bannerUpdated = document.getElementById("banner-updated");
    const topBanner = document.getElementById("top-banner");

    const overallTitle = document.getElementById("overall-title");
    const overallChip = document.getElementById("overall-chip");

    const trafficGreen = document.getElementById("traffic-green");
    const trafficAmber = document.getElementById("traffic-amber");
    const trafficRed = document.getElementById("traffic-red");

    const remoteCountEl = document.getElementById("remote-count");
    const localCountEl = document.getElementById("local-count");

    const webDot = document.getElementById("web-status-dot");
    const webText = document.getElementById("web-status-text");
    const pfDot = document.getElementById("pf-status-dot");
    const pfText = document.getElementById("pf-status-text");
    const currentRemoteEl = document.getElementById("current-remote");

    const lastRunEl = document.getElementById("last-run");
    const lastRestartEl = document.getElementById("last-restart");
    const lastDownloadEl = document.getElementById("last-download");
    const logTailEl = document.getElementById("log-tail");
    const chkDOutputEl = document.getElementById("chk-d-output");

    const btnRefresh = document.getElementById("btn-refresh");
    const btnRunD = document.getElementById("btn-run-d");
    const btnRunDSpinner = document.getElementById("btn-run-d-spinner");
    const btnRunDLabel = document.getElementById("btn-run-d-label");
    const btnSyncNow = document.getElementById("btn-sync-now");
    const btnSyncNowSpinner = document.getElementById("btn-sync-now-spinner");
    const btnSyncNowLabel = document.getElementById("btn-sync-now-label");
    const btnRestartPf = document.getElementById("btn-restart-pf");
    const btnRestartPfSpinner = document.getElementById("btn-restart-pf-spinner");
    const btnRestartPfLabel = document.getElementById("btn-restart-pf-label");
    const btnRestartWeb = document.getElementById("btn-restart-web");
    const btnRestartWebSpinner = document.getElementById("btn-restart-web-spinner");
    const btnRestartWebLabel = document.getElementById("btn-restart-web-label");

    // Technical details elements
    const techSourceName = document.getElementById("tech-source-name");
    const techRemotePath = document.getElementById("tech-remote-path");
    const techLocalPath = document.getElementById("tech-local-path");

    function setServiceDot(dotEl, textEl, status) {
        const s = (status || "").toLowerCase();
        const up = s === "active" || s === "running";
        dotEl.classList.toggle("off", !up);
        textEl.textContent = up ? "RUNNING" : (status || "UNKNOWN").toUpperCase();
    }

    function setTrafficLights(severity) {
        const sev = (severity || "UNKNOWN").toUpperCase();
        trafficGreen.classList.add("off");
        trafficAmber.classList.add("off");
        trafficRed.classList.add("off");

        if (sev === "OK") {
            trafficGreen.classList.remove("off");
        } else if (sev === "WARN") {
            trafficAmber.classList.remove("off");
        } else if (sev === "ERROR") {
            trafficRed.classList.remove("off");
        } else {
            trafficAmber.classList.remove("off");
        }
    }

    function setBannerForSeverity(severity) {
        const sev = (severity || "UNKNOWN").toUpperCase();
        if (sev === "OK") {
            topBanner.style.background = "linear-gradient(90deg, #0b7a39, #059669)";
            bannerPill.textContent = "OK";
        } else if (sev === "WARN") {
            topBanner.style.background = "linear-gradient(90deg, #92400e, #f97316)";
            bannerPill.textContent = "WARN";
        } else if (sev === "ERROR") {
            topBanner.style.background = "linear-gradient(90deg, #b91c1c, #ef4444)";
            bannerPill.textContent = "ERROR";
        } else {
            topBanner.style.background = "linear-gradient(90deg, #4b5563, #6b7280)";
            bannerPill.textContent = "UNKNOWN";
        }
    }

    async function refreshStatus() {
        btnRefresh.disabled = true;
        try {
            const resp = await fetch("/api/status");
            const data = await resp.json();

            const nowStr = data.now || "";
            bannerUpdated.textContent = nowStr ? "Updated: " + nowStr : "Updated: --";

            const overall = data.overall || {};
            const severity = overall.severity || "UNKNOWN";
            const statusText = overall.status_text || "Status unknown";

            overallTitle.textContent = statusText;
            overallChip.textContent = severity;
            overallChip.classList.remove("error", "warn");
            if (severity.toUpperCase() === "ERROR") {
                overallChip.classList.add("error");
            } else if (severity.toUpperCase() === "WARN") {
                overallChip.classList.add("warn");
            }
            bannerText.textContent = statusText;

            setTrafficLights(severity);
            setBannerForSeverity(severity);

            const rc = overall.remote_count;
            const lc = overall.local_count;
            remoteCountEl.textContent = (rc !== null && rc !== undefined) ? rc : "—";
            localCountEl.textContent = (lc !== null && lc !== undefined) ? lc : "—";

            setServiceDot(webDot, webText, data.web_status);
            setServiceDot(pfDot, pfText, data.pf_status);

            currentRemoteEl.textContent = data.current_remote || "--";

            // Update technical details section
            const sourceDetails = data.source_details || {};
            if (techSourceName) techSourceName.textContent = sourceDetails.source_name || "--";
            if (techRemotePath) techRemotePath.textContent = sourceDetails.remote_path || "--";
            if (techLocalPath) techLocalPath.textContent = sourceDetails.local_path || "--";

            const act = data.activity || {};
            lastRunEl.textContent = act.last_run || nowStr || "—";
            lastRestartEl.textContent = act.last_service_restart || "—";
            lastDownloadEl.textContent = act.last_file_download || "—";
            logTailEl.textContent = (act.log_tail || "").trim() || "(no log data)";
        } catch (err) {
            console.error("Failed to refresh status", err);
            bannerText.textContent = "Error fetching status";
            setBannerForSeverity("ERROR");
            overallTitle.textContent = "Status unknown";
            overallChip.textContent = "ERROR";
        } finally {
            btnRefresh.disabled = false;
        }
    }

    async function runChkSyncD() {
        btnRunD.disabled = true;
        btnRunDSpinner.style.display = "inline-block";
        btnRunDLabel.textContent = "Running…";
        try {
            const resp = await fetch("/api/run-chk-syncd", { method: "POST" });
            const data = await resp.json();
            chkDOutputEl.textContent = (data.output || "").trim() || "(no output)";
        } catch (err) {
            console.error("Failed to run chk_sync.sh --d", err);
            chkDOutputEl.textContent = "Error running chk_sync.sh --d: " + err;
        } finally {
            btnRunD.disabled = false;
            btnRunDSpinner.style.display = "none";
            btnRunDLabel.textContent = "Run chk_sync.sh --d";
        }
    }

    async function restartPfService() {
        btnRestartPf.disabled = true;
        btnRestartPfSpinner.style.display = "inline-block";
        btnRestartPfLabel.textContent = "Restarting…";
        try {
            const resp = await fetch("/api/restart-pf", { method: "POST" });
            const data = await resp.json();
            if (data.ok) {
                alert("Picframe service restarted successfully!\n\n" + (data.output || ""));
                await refreshStatus();
            } else {
                alert("Failed to restart Picframe service:\n\n" + (data.output || "Error"));
            }
        } catch (err) {
            console.error("Failed to restart Picframe service", err);
            alert("Error restarting Picframe service: " + err);
        } finally {
            btnRestartPf.disabled = false;
            btnRestartPfSpinner.style.display = "none";
            btnRestartPfLabel.textContent = "Restart Picframe Service";
        }
    }

    async function restartWebService() {
        btnRestartWeb.disabled = true;
        btnRestartWebSpinner.style.display = "inline-block";
        btnRestartWebLabel.textContent = "Restarting…";
        try {
            const resp = await fetch("/api/restart-web", { method: "POST" });
            const data = await resp.json();
            if (data.ok) {
                alert("Web service restarted successfully!\n\nNote: This page may reload or become temporarily unavailable.\n\n" + (data.output || ""));
                setTimeout(() => {
                    window.location.reload();
                }, 2000);
            } else {
                alert("Failed to restart web service:\n\n" + (data.output || "Error"));
            }
        } catch (err) {
            console.error("Failed to restart web service", err);
            alert("Error restarting web service: " + err);
        } finally {
            btnRestartWeb.disabled = false;
            btnRestartWebSpinner.style.display = "none";
            btnRestartWebLabel.textContent = "Restart Web Service";
        }
    }

    async function syncNow() {
        btnSyncNow.disabled = true;
        btnSyncNowSpinner.style.display = "inline-block";
        btnSyncNowLabel.textContent = "Syncing…";
        try {
            const resp = await fetch("/api/sync-now", { method: "POST" });
            const data = await resp.json();
            if (data.ok) {
                alert("Sync completed successfully!\n\nPhotos have been synced from the cloud.");
                await refreshStatus();
            } else {
                alert("Sync failed:\n\n" + (data.output || "Error"));
            }
        } catch (err) {
            console.error("Failed to sync", err);
            alert("Error syncing: " + err);
        } finally {
            btnSyncNow.disabled = false;
            btnSyncNowSpinner.style.display = "none";
            btnSyncNowLabel.textContent = "🔄 Sync Now";
        }
    }

    btnRefresh.addEventListener("click", refreshStatus);
    btnRunD.addEventListener("click", runChkSyncD);
    btnSyncNow.addEventListener("click", syncNow);
    btnRestartPf.addEventListener("click", restartPfService);
    btnRestartWeb.addEventListener("click", restartWebService);

    // Auto-refresh current image thumbnail
    const thumbnailImg = document.getElementById("current-image-thumbnail");
    if (thumbnailImg) {
        function refreshThumbnail() {
            // Add timestamp to bypass cache
            const timestamp = new Date().getTime();
            thumbnailImg.src = `/api/current-image?t=${timestamp}`;
        }

        // Refresh thumbnail every 30 seconds
        setInterval(refreshThumbnail, 30000);
    }

    // Initial load
    refreshStatus();
    setInterval(refreshStatus, 15000);
}

// =============================================================================
// SOURCES MANAGER FUNCTIONALITY (from sources.js)
// =============================================================================

const sourcesState = {
    currentRemote: '',
    currentPath: [],
    remotes: [],
    localDirs: [],
    sources: []
};

let sourcesElements = {};

function initSourcesManager() {
    initSourcesElements();
    initSourcesEventListeners();
    loadSourcesInitialData();
}

function initSourcesElements() {
    sourcesElements = {
        sourceId: document.getElementById('input-source-id'),
        label: document.getElementById('input-label'),
        remote: document.getElementById('input-remote'),
        remotePath: document.getElementById('input-remote-path'),
        localDir: document.getElementById('input-local-dir'),
        newDirName: document.getElementById('input-new-dir-name'),
        newDirContainer: document.getElementById('new-dir-input-container'),
        enabled: document.getElementById('input-enabled'),
        btnTest: document.getElementById('btn-test-connection'),
        btnSave: document.getElementById('btn-save-source'),
        sourcesTbody: document.getElementById('sources-tbody'),
        breadcrumb: document.getElementById('breadcrumb-path'),
        remoteDirList: document.getElementById('remote-dir-list'),
        statusMessage: document.getElementById('status-message'),
        form: document.getElementById('add-source-form')
    };
}

function initSourcesEventListeners() {
    sourcesElements.remote.addEventListener('change', onRemoteChange);
    sourcesElements.localDir.addEventListener('change', onLocalDirChange);
    sourcesElements.form.addEventListener('submit', onFormSubmit);
    sourcesElements.btnTest.addEventListener('click', onTestConnection);
}

async function loadSourcesInitialData() {
    await Promise.all([
        loadSources(),
        loadRcloneRemotes(),
        loadLocalDirs()
    ]);
}

async function loadSources() {
    try {
        const response = await fetch('/api/sources');
        const data = await response.json();
        
        sourcesState.sources = data.sources || [];
        renderSourcesTable();
    } catch (err) {
        console.error('Failed to load sources:', err);
        sourcesElements.sourcesTbody.innerHTML = `
            <tr>
                <td colspan="6" class="loading-cell" style="color: #fca5a5;">
                    Error loading sources: ${escapeHtml(err.message)}
                </td>
            </tr>
        `;
    }
}

function renderSourcesTable() {
    if (sourcesState.sources.length === 0) {
        sourcesElements.sourcesTbody.innerHTML = `
            <tr>
                <td colspan="6" class="loading-cell">No sources configured yet</td>
            </tr>
        `;
        return;
    }

    const rows = sourcesState.sources.map(source => {
        const statusBadges = [];

        if (source.active) {
            // Active sources only show "Active"
            statusBadges.push('<span class="source-status-badge active">Active</span>');
        } else if (source.enabled) {
            // Non-active enabled sources show "Ready"
            statusBadges.push('<span class="source-status-badge enabled">Ready</span>');
        } else {
            // Disabled sources show "Disabled"
            statusBadges.push('<span class="source-status-badge disabled">Disabled</span>');
        }

        const activateBtn = source.active
            ? ''
            : `<button class="btn-small" onclick="activateSource('${escapeHtml(source.path)}', '${escapeHtml(source.id)}')">Activate</button> `;

        return `
            <tr>
                <td><strong>${escapeHtml(source.id)}</strong></td>
                <td>${escapeHtml(source.label)}</td>
                <td><code>${escapeHtml(source.remote || 'default')}</code></td>
                <td><code>${escapeHtml(source.path)}</code></td>
                <td>${statusBadges.join(' ')}</td>
                <td style="white-space: nowrap;">
                    ${activateBtn}<button class="btn-small btn-danger" onclick="deleteSource('${escapeHtml(source.id)}')">Delete</button>
                </td>
            </tr>
        `;
    }).join('');

    sourcesElements.sourcesTbody.innerHTML = rows;
}

async function loadRcloneRemotes() {
    try {
        const response = await fetch('/api/rclone/remotes');
        const data = await response.json();
        
        if (!data.ok) {
            throw new Error(data.error || 'Failed to load remotes');
        }
        
        sourcesState.remotes = data.remotes || [];
        renderRemoteDropdown();
    } catch (err) {
        console.error('Failed to load remotes:', err);
        sourcesElements.remote.innerHTML = `<option value="">Error: ${escapeHtml(err.message)}</option>`;
        showSourcesStatus('error', `Failed to load rclone remotes: ${err.message}`);
    }
}

function renderRemoteDropdown() {
    if (sourcesState.remotes.length === 0) {
        sourcesElements.remote.innerHTML = `<option value="">No remotes configured</option>`;
        return;
    }
    
    const options = sourcesState.remotes.map(remote => 
        `<option value="${escapeHtml(remote)}">${escapeHtml(remote)}</option>`
    ).join('');
    
    sourcesElements.remote.innerHTML = `
        <option value="">Select a remote...</option>
        ${options}
    `;
}

async function loadLocalDirs() {
    try {
        const response = await fetch('/api/local/list-dirs');
        const data = await response.json();
        
        if (!data.ok) {
            throw new Error(data.error || 'Failed to load directories');
        }
        
        sourcesState.localDirs = data.dirs || [];
        renderLocalDirDropdown();
    } catch (err) {
        console.error('Failed to load local dirs:', err);
        sourcesElements.localDir.innerHTML = `<option value="">Error: ${escapeHtml(err.message)}</option>`;
    }
}

function renderLocalDirDropdown() {
    if (sourcesState.localDirs.length === 0) {
        sourcesElements.localDir.innerHTML = `
            <option value="">No directories found</option>
            <option value="new">+ Create new directory</option>
        `;
        return;
    }
    
    const options = sourcesState.localDirs.map(dir => 
        `<option value="/home/pi/Pictures/${escapeHtml(dir)}">/home/pi/Pictures/${escapeHtml(dir)}</option>`
    ).join('');
    
    sourcesElements.localDir.innerHTML = `
        <option value="">Select a directory...</option>
        ${options}
        <option value="new">+ Create new directory</option>
    `;
}

function onRemoteChange() {
    const selectedRemote = sourcesElements.remote.value;

    if (!selectedRemote) {
        sourcesState.currentRemote = '';
        sourcesState.currentPath = [];
        renderBreadcrumb();
        renderRemoteDirs([]);
        return;
    }

    sourcesState.currentRemote = selectedRemote;
    sourcesState.currentPath = [];
    renderBreadcrumb();
    loadRemoteDirs();
}

function onLocalDirChange() {
    const selectedValue = sourcesElements.localDir.value;

    if (selectedValue === 'new') {
        sourcesElements.newDirContainer.style.display = 'block';
        sourcesElements.newDirName.required = true;
        sourcesElements.newDirName.focus();
    } else {
        sourcesElements.newDirContainer.style.display = 'none';
        sourcesElements.newDirName.required = false;
        sourcesElements.newDirName.value = '';
    }
}

async function loadRemoteDirs() {
    if (!sourcesState.currentRemote) {
        renderRemoteDirs([]);
        return;
    }
    
    sourcesElements.remoteDirList.innerHTML = `<div class="dir-item loading">Loading directories...</div>`;
    
    try {
        const response = await fetch('/api/rclone/list-dirs', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                remote: sourcesState.currentRemote,
                path: sourcesState.currentPath.join('/')
            })
        });
        
        const data = await response.json();
        
        if (!data.ok) {
            throw new Error(data.error || 'Failed to list directories');
        }
        
        renderRemoteDirs(data.dirs || []);
    } catch (err) {
        console.error('Failed to load remote dirs:', err);
        sourcesElements.remoteDirList.innerHTML = `
            <div class="dir-item placeholder" style="color: #fca5a5;">
                Error: ${escapeHtml(err.message)}
            </div>
        `;
    }
}

function renderRemoteDirs(dirs) {
    if (dirs.length === 0) {
        sourcesElements.remoteDirList.innerHTML = `<div class="dir-item placeholder">No directories found</div>`;
        return;
    }
    
    const items = dirs.map(dir => {
        // Handle both new object format and legacy string format
        const dirData = typeof dir === 'string' ? { name: dir, valid: true } : dir;
        const { name, valid, trimmed_name, reason } = dirData;

        if (!valid) {
            // Blocked directory - show with warning
            return `
                <div class="dir-item-blocked" title="${escapeHtml(reason)}">
                    <span class="dir-warning-icon">⚠️</span>
                    <span class="dir-name-blocked">${escapeHtml(name)}</span>
                    <span class="dir-warning-text">
                        Invalid name - rename to "${escapeHtml(trimmed_name)}"
                    </span>
                </div>
            `;
        } else {
            // Valid directory - clickable
            return `<div class="dir-item" data-dirname="${escapeHtml(name)}">${escapeHtml(name)}</div>`;
        }
    }).join('');
    
    sourcesElements.remoteDirList.innerHTML = items;
    
    sourcesElements.remoteDirList.querySelectorAll('.dir-item[data-dirname]').forEach(item => {
        item.addEventListener('click', () => {
            const dirname = item.getAttribute('data-dirname');
            navigateToDir(dirname);
        });
    });
}

function navigateToDir(dirname) {
    sourcesState.currentPath.push(dirname);
    renderBreadcrumb();
    loadRemoteDirs();
    updateRemotePathInput();
}

function navigateToLevel(level) {
    sourcesState.currentPath = sourcesState.currentPath.slice(0, level);
    renderBreadcrumb();
    loadRemoteDirs();
    updateRemotePathInput();
}

function renderBreadcrumb() {
    const parts = [`<span class="breadcrumb-item root" data-level="0">Root</span>`];
    
    sourcesState.currentPath.forEach((part, index) => {
        parts.push(`<span class="breadcrumb-item" data-level="${index + 1}">${escapeHtml(part)}</span>`);
    });
    
    sourcesElements.breadcrumb.innerHTML = parts.join('');
    
    sourcesElements.breadcrumb.querySelectorAll('.breadcrumb-item').forEach(item => {
        item.addEventListener('click', () => {
            const level = parseInt(item.getAttribute('data-level'));
            navigateToLevel(level);
        });
    });
}

function updateRemotePathInput() {
    sourcesElements.remotePath.value = sourcesState.currentPath.join('/');
}

async function onTestConnection() {
    const remote = sourcesElements.remote.value;
    const path = sourcesElements.remotePath.value;
    
    if (!remote) {
        showSourcesStatus('error', 'Please select a remote first');
        return;
    }
    
    const fullPath = path ? `${remote}${path}` : remote;
    
    sourcesElements.btnTest.disabled = true;
    sourcesElements.btnTest.textContent = 'Testing...';
    showSourcesStatus('info', 'Testing connection...');
    
    try {
        const response = await fetch('/api/config/test-remote', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ remote: fullPath })
        });
        
        const data = await response.json();
        
        if (data.ok) {
            showSourcesStatus('success', `Connection successful! Found ${data.file_count} items.`);
        } else {
            showSourcesStatus('error', `Connection failed: ${data.error}`);
        }
    } catch (err) {
        showSourcesStatus('error', `Test failed: ${err.message}`);
    } finally {
        sourcesElements.btnTest.disabled = false;
        sourcesElements.btnTest.textContent = 'Test Connection';
    }
}

async function onFormSubmit(event) {
    event.preventDefault();

    // Handle new directory creation
    let localPath = sourcesElements.localDir.value;
    let createDirectory = false;

    if (localPath === 'new') {
        const newDirName = sourcesElements.newDirName.value.trim();
        if (!newDirName) {
            showSourcesStatus('error', 'Please enter a directory name');
            return;
        }

        // Validate directory name (alphanumeric, hyphens, underscores only)
        if (!/^[a-zA-Z0-9_-]+$/.test(newDirName)) {
            showSourcesStatus('error', 'Directory name must contain only letters, numbers, hyphens, and underscores');
            return;
        }

        // Construct full path
        localPath = `/home/pi/Pictures/${newDirName}`;
        createDirectory = true;
    }

    // Gather form data
    const formData = {
        source_id: sourcesElements.sourceId.value.trim(),
        label: sourcesElements.label.value.trim(),
        rclone_remote: buildFullRemotePath(),
        path: localPath,
        enabled: sourcesElements.enabled.checked,
        create_directory: createDirectory
    };

    // Validate
    if (!formData.source_id) {
        showSourcesStatus('error', 'Source ID is required');
        return;
    }

    if (!formData.label) {
        showSourcesStatus('error', 'Label is required');
        return;
    }

    if (!formData.rclone_remote) {
        showSourcesStatus('error', 'Please select a remote');
        return;
    }

    if (!formData.path) {
        showSourcesStatus('error', 'Please select or create a local directory');
        return;
    }

    // Show confirmation dialog
    const confirmMessage = `Please confirm the new photo source:\n\n` +
        `Name: ${formData.label}\n` +
        `Cloud Location: ${formData.rclone_remote}\n` +
        `Local Storage: ${formData.path}\n` +
        (createDirectory ? `\nA new directory will be created.\n` : '') +
        `\nDo you want to proceed?`;

    if (!confirm(confirmMessage)) {
        return;
    }

    // Disable submit button
    sourcesElements.btnSave.disabled = true;
    sourcesElements.btnSave.textContent = 'Saving...';
    showSourcesStatus('info', 'Creating new source...');

    try {
        const response = await fetch('/api/sources/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(formData)
        });

        const data = await response.json();

        if (data.ok) {
            showSourcesStatus('success', `Source "${formData.source_id}" created successfully!`);

            // Reset form
            sourcesElements.form.reset();
            sourcesState.currentPath = [];
            renderBreadcrumb();
            renderRemoteDirs([]);

            // Reload sources
            await loadSources();
        } else {
            showSourcesStatus('error', `Failed to create source: ${data.error}`);
        }
    } catch (err) {
        showSourcesStatus('error', `Error: ${err.message}`);
    } finally {
        sourcesElements.btnSave.disabled = false;
        sourcesElements.btnSave.textContent = 'Save New Source';
    }
}

function buildFullRemotePath() {
    const remote = sourcesElements.remote.value;
    const path = sourcesElements.remotePath.value;
    
    if (!remote) {
        return '';
    }
    
    return path ? `${remote}${path}` : remote;
}

function showSourcesStatus(type, message) {
    sourcesElements.statusMessage.className = `status-message ${type}`;
    sourcesElements.statusMessage.textContent = message;
    sourcesElements.statusMessage.style.display = 'block';
    
    if (type === 'success' || type === 'info') {
        setTimeout(() => {
            sourcesElements.statusMessage.style.display = 'none';
        }, 5000);
    }
}

async function activateSource(targetPath, sourceId) {
    if (!confirm(`Switch to "${sourceId}"?\n\nThis will sync photos from the cloud and display them on your frame.`)) {
        return;
    }

    showSourcesStatus('info', `Activating "${sourceId}" and syncing photos...`);

    try {
        const response = await fetch('/api/frame-live', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ target_dir: targetPath })
        });

        const data = await response.json();

        if (data.ok) {
            if (data.sync_triggered) {
                showSourcesStatus('success', `"${sourceId}" activated and synced successfully!`);
            } else {
                showSourcesStatus('success', `"${sourceId}" activated successfully!`);
            }
            // Reload sources to update active status
            await loadSources();
            // Refresh main dashboard status
            if (typeof refreshStatus === 'function') {
                await refreshStatus();
            }
        } else {
            showSourcesStatus('error', `Failed to activate: ${data.error}`);
        }
    } catch (err) {
        showSourcesStatus('error', `Error activating source: ${err.message}`);
    }
}

async function deleteSource(sourceId) {
    if (!confirm(`Are you sure you want to delete source "${sourceId}"?\n\nThis will remove it from the configuration but will NOT delete any files.`)) {
        return;
    }

    showSourcesStatus('info', `Deleting source "${sourceId}"...`);

    try {
        const response = await fetch('/api/sources/delete', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ source_id: sourceId })
        });

        const data = await response.json();

        if (data.ok) {
            showSourcesStatus('success', `Source "${sourceId}" deleted successfully!`);
            await loadSources();
        } else {
            showSourcesStatus('error', `Failed to delete source: ${data.error}`);
        }
    } catch (err) {
        showSourcesStatus('error', `Error deleting source: ${err.message}`);
    }
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
