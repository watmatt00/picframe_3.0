/**
 * Sources Manager - JavaScript
 * Handles directory browsing, source management, and API interactions
 */

// State management
const state = {
    currentRemote: '',
    currentPath: [],
    remotes: [],
    localDirs: [],
    sources: []
};

// DOM elements
let elements = {};

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    initElements();
    initEventListeners();
    loadInitialData();
});

/**
 * Initialize DOM element references
 */
function initElements() {
    elements = {
        // Form inputs
        sourceId: document.getElementById('input-source-id'),
        label: document.getElementById('input-label'),
        remote: document.getElementById('input-remote'),
        remotePath: document.getElementById('input-remote-path'),
        localDir: document.getElementById('input-local-dir'),
        newDirName: document.getElementById('input-new-dir-name'),
        newDirContainer: document.getElementById('new-dir-input-container'),
        enabled: document.getElementById('input-enabled'),

        // Buttons
        btnTest: document.getElementById('btn-test-connection'),
        btnSave: document.getElementById('btn-save-source'),

        // Display areas
        sourcesTbody: document.getElementById('sources-tbody'),
        breadcrumb: document.getElementById('breadcrumb-path'),
        remoteDirList: document.getElementById('remote-dir-list'),
        statusMessage: document.getElementById('status-message'),

        // Form
        form: document.getElementById('add-source-form')
    };
}

/**
 * Initialize event listeners
 */
function initEventListeners() {
    // Remote dropdown change
    elements.remote.addEventListener('change', onRemoteChange);

    // Local directory dropdown change
    elements.localDir.addEventListener('change', onLocalDirChange);

    // Form submission
    elements.form.addEventListener('submit', onFormSubmit);

    // Test connection button
    elements.btnTest.addEventListener('click', onTestConnection);
}

/**
 * Load initial data
 */
async function loadInitialData() {
    await Promise.all([
        loadSources(),
        loadRcloneRemotes(),
        loadLocalDirs()
    ]);
}

/**
 * Load existing sources from API
 */
async function loadSources() {
    try {
        const response = await fetch('/api/sources');
        const data = await response.json();
        
        state.sources = data.sources || [];
        renderSourcesTable();
    } catch (err) {
        console.error('Failed to load sources:', err);
        elements.sourcesTbody.innerHTML = `
            <tr>
                <td colspan="5" class="loading-cell" style="color: #fca5a5;">
                    Error loading sources: ${err.message}
                </td>
            </tr>
        `;
    }
}

/**
 * Render sources table
 */
function renderSourcesTable() {
    if (state.sources.length === 0) {
        elements.sourcesTbody.innerHTML = `
            <tr>
                <td colspan="5" class="loading-cell">
                    No sources configured yet
                </td>
            </tr>
        `;
        return;
    }
    
    const rows = state.sources.map(source => {
        const statusBadges = [];
        
        if (source.active) {
            statusBadges.push('<span class="source-status-badge active">Active</span>');
        }
        if (source.enabled) {
            statusBadges.push('<span class="source-status-badge enabled">Enabled</span>');
        } else {
            statusBadges.push('<span class="source-status-badge disabled">Disabled</span>');
        }
        
        return `
            <tr>
                <td><strong>${escapeHtml(source.id)}</strong></td>
                <td>${escapeHtml(source.label)}</td>
                <td><code>${escapeHtml(source.path)}</code></td>
                <td><code>${escapeHtml(source.remote || 'default')}</code></td>
                <td>${statusBadges.join(' ')}</td>
            </tr>
        `;
    }).join('');
    
    elements.sourcesTbody.innerHTML = rows;
}

/**
 * Load rclone remotes
 */
async function loadRcloneRemotes() {
    try {
        const response = await fetch('/api/rclone/remotes');
        const data = await response.json();
        
        if (!data.ok) {
            throw new Error(data.error || 'Failed to load remotes');
        }
        
        state.remotes = data.remotes || [];
        renderRemoteDropdown();
    } catch (err) {
        console.error('Failed to load remotes:', err);
        elements.remote.innerHTML = `
            <option value="">Error: ${err.message}</option>
        `;
        showStatus('error', `Failed to load rclone remotes: ${err.message}`);
    }
}

/**
 * Render remote dropdown
 */
function renderRemoteDropdown() {
    if (state.remotes.length === 0) {
        elements.remote.innerHTML = `
            <option value="">No remotes configured</option>
        `;
        return;
    }
    
    const options = state.remotes.map(remote => 
        `<option value="${escapeHtml(remote)}">${escapeHtml(remote)}</option>`
    ).join('');
    
    elements.remote.innerHTML = `
        <option value="">Select a remote...</option>
        ${options}
    `;
}

/**
 * Load local directories
 */
async function loadLocalDirs() {
    try {
        const response = await fetch('/api/local/list-dirs');
        const data = await response.json();
        
        if (!data.ok) {
            throw new Error(data.error || 'Failed to load directories');
        }
        
        state.localDirs = data.dirs || [];
        renderLocalDirDropdown();
    } catch (err) {
        console.error('Failed to load local dirs:', err);
        elements.localDir.innerHTML = `
            <option value="">Error: ${err.message}</option>
        `;
    }
}

/**
 * Render local directory dropdown
 */
function renderLocalDirDropdown() {
    if (state.localDirs.length === 0) {
        elements.localDir.innerHTML = `
            <option value="">No directories found</option>
            <option value="new">+ Create new directory</option>
        `;
        return;
    }
    
    const options = state.localDirs.map(dir => 
        `<option value="/home/pi/Pictures/${escapeHtml(dir)}">/home/pi/Pictures/${escapeHtml(dir)}</option>`
    ).join('');
    
    elements.localDir.innerHTML = `
        <option value="">Select a directory...</option>
        ${options}
        <option value="new">+ Create new directory</option>
    `;
}

/**
 * Handle remote selection change
 */
function onRemoteChange() {
    const selectedRemote = elements.remote.value;

    if (!selectedRemote) {
        state.currentRemote = '';
        state.currentPath = [];
        renderBreadcrumb();
        renderRemoteDirs([]);
        return;
    }

    state.currentRemote = selectedRemote;
    state.currentPath = [];
    renderBreadcrumb();
    loadRemoteDirs();
}

/**
 * Handle local directory selection change
 */
function onLocalDirChange() {
    const selectedValue = elements.localDir.value;
    console.log('Local dir changed to:', selectedValue);
    console.log('newDirContainer element:', elements.newDirContainer);

    if (selectedValue === 'new') {
        // Show the new directory input field
        console.log('Showing new dir input');
        elements.newDirContainer.style.display = 'block';
        elements.newDirName.required = true;
        elements.newDirName.focus();
    } else {
        // Hide the new directory input field
        console.log('Hiding new dir input');
        elements.newDirContainer.style.display = 'none';
        elements.newDirName.required = false;
        elements.newDirName.value = '';
    }
}

/**
 * Load directories from remote path
 */
async function loadRemoteDirs() {
    if (!state.currentRemote) {
        renderRemoteDirs([]);
        return;
    }
    
    // Show loading state
    elements.remoteDirList.innerHTML = `
        <div class="dir-item loading">Loading directories...</div>
    `;
    
    try {
        const response = await fetch('/api/rclone/list-dirs', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                remote: state.currentRemote,
                path: state.currentPath.join('/')
            })
        });
        
        const data = await response.json();
        
        if (!data.ok) {
            throw new Error(data.error || 'Failed to list directories');
        }
        
        renderRemoteDirs(data.dirs || []);
    } catch (err) {
        console.error('Failed to load remote dirs:', err);
        elements.remoteDirList.innerHTML = `
            <div class="dir-item placeholder" style="color: #fca5a5;">
                Error: ${escapeHtml(err.message)}
            </div>
        `;
    }
}

/**
 * Render remote directories list
 */
function renderRemoteDirs(dirs) {
    if (dirs.length === 0) {
        elements.remoteDirList.innerHTML = `
            <div class="dir-item placeholder">No directories found</div>
        `;
        return;
    }
    
    const items = dirs.map(dir => 
        `<div class="dir-item" data-dirname="${escapeHtml(dir)}">${escapeHtml(dir)}</div>`
    ).join('');
    
    elements.remoteDirList.innerHTML = items;
    
    // Add click handlers
    elements.remoteDirList.querySelectorAll('.dir-item[data-dirname]').forEach(item => {
        item.addEventListener('click', () => {
            const dirname = item.getAttribute('data-dirname');
            navigateToDir(dirname);
        });
    });
}

/**
 * Navigate to a subdirectory
 */
function navigateToDir(dirname) {
    state.currentPath.push(dirname);
    renderBreadcrumb();
    loadRemoteDirs();
    updateRemotePathInput();
}

/**
 * Navigate to a specific path level
 */
function navigateToLevel(level) {
    state.currentPath = state.currentPath.slice(0, level);
    renderBreadcrumb();
    loadRemoteDirs();
    updateRemotePathInput();
}

/**
 * Render breadcrumb navigation
 */
function renderBreadcrumb() {
    const parts = [
        `<span class="breadcrumb-item root" data-level="0">Root</span>`
    ];
    
    state.currentPath.forEach((part, index) => {
        parts.push(
            `<span class="breadcrumb-item" data-level="${index + 1}">${escapeHtml(part)}</span>`
        );
    });
    
    elements.breadcrumb.innerHTML = parts.join('');
    
    // Add click handlers
    elements.breadcrumb.querySelectorAll('.breadcrumb-item').forEach(item => {
        item.addEventListener('click', () => {
            const level = parseInt(item.getAttribute('data-level'));
            navigateToLevel(level);
        });
    });
}

/**
 * Update hidden remote path input
 */
function updateRemotePathInput() {
    elements.remotePath.value = state.currentPath.join('/');
}

/**
 * Test connection to remote
 */
async function onTestConnection() {
    const remote = elements.remote.value;
    const path = elements.remotePath.value;
    
    if (!remote) {
        showStatus('error', 'Please select a remote first');
        return;
    }
    
    // Build full remote path
    const fullPath = path ? `${remote}${path}` : remote;
    
    // Disable button
    elements.btnTest.disabled = true;
    elements.btnTest.textContent = 'Testing...';
    showStatus('info', 'Testing connection...');
    
    try {
        const response = await fetch('/api/config/test-remote', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ remote: fullPath })
        });
        
        const data = await response.json();
        
        if (data.ok) {
            showStatus('success', `Connection successful! Found ${data.file_count} items.`);
        } else {
            showStatus('error', `Connection failed: ${data.error}`);
        }
    } catch (err) {
        showStatus('error', `Test failed: ${err.message}`);
    } finally {
        elements.btnTest.disabled = false;
        elements.btnTest.textContent = 'Test Connection';
    }
}

/**
 * Handle form submission
 */
async function onFormSubmit(event) {
    event.preventDefault();

    // Handle new directory creation
    let localPath = elements.localDir.value;
    let createDirectory = false;

    if (localPath === 'new') {
        const newDirName = elements.newDirName.value.trim();
        if (!newDirName) {
            showStatus('error', 'Please enter a directory name');
            return;
        }

        // Validate directory name (alphanumeric, hyphens, underscores only)
        if (!/^[a-zA-Z0-9_-]+$/.test(newDirName)) {
            showStatus('error', 'Directory name must contain only letters, numbers, hyphens, and underscores');
            return;
        }

        // Construct full path
        localPath = `/home/pi/Pictures/${newDirName}`;
        createDirectory = true;
    }

    // Gather form data
    const formData = {
        source_id: elements.sourceId.value.trim(),
        label: elements.label.value.trim(),
        rclone_remote: buildFullRemotePath(),
        path: localPath,
        enabled: elements.enabled.checked,
        create_directory: createDirectory
    };

    // Validate
    if (!formData.source_id) {
        showStatus('error', 'Source ID is required');
        return;
    }

    if (!formData.label) {
        showStatus('error', 'Label is required');
        return;
    }

    if (!formData.rclone_remote) {
        showStatus('error', 'Please select a remote');
        return;
    }

    if (!formData.path) {
        showStatus('error', 'Please select or create a local directory');
        return;
    }
    
    // Disable submit button
    elements.btnSave.disabled = true;
    elements.btnSave.textContent = 'Saving...';
    showStatus('info', 'Creating new source...');
    
    try {
        const response = await fetch('/api/sources/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(formData)
        });
        
        const data = await response.json();
        
        if (data.ok) {
            showStatus('success', `Source "${formData.source_id}" created successfully!`);
            
            // Reset form
            elements.form.reset();
            state.currentPath = [];
            renderBreadcrumb();
            renderRemoteDirs([]);
            
            // Reload sources
            await loadSources();
        } else {
            showStatus('error', `Failed to create source: ${data.error}`);
        }
    } catch (err) {
        showStatus('error', `Error: ${err.message}`);
    } finally {
        elements.btnSave.disabled = false;
        elements.btnSave.textContent = 'Save New Source';
    }
}

/**
 * Build full remote path from current state
 */
function buildFullRemotePath() {
    const remote = elements.remote.value;
    const path = elements.remotePath.value;
    
    if (!remote) {
        return '';
    }
    
    return path ? `${remote}${path}` : remote;
}

/**
 * Show status message
 */
function showStatus(type, message) {
    elements.statusMessage.className = `status-message ${type}`;
    elements.statusMessage.textContent = message;
    elements.statusMessage.style.display = 'block';
    
    // Auto-hide after 5 seconds for success/info
    if (type === 'success' || type === 'info') {
        setTimeout(() => {
            elements.statusMessage.style.display = 'none';
        }, 5000);
    }
}

/**
 * Escape HTML to prevent XSS
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
