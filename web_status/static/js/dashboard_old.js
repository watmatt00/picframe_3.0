function applyStatusLights(level) {
    const dot = document.getElementById('statusDot');
    const banner = document.getElementById('banner');
    const chip = document.getElementById('statusLabel');

    dot.classList.remove('ok', 'warn', 'err');
    chip.classList.remove('ok', 'warn', 'err');

    let bg = 'linear-gradient(to right, #111827, #020617)';
    let border = '1px solid rgba(55,65,81,0.9)';

    if (level === 'ok') {
        dot.classList.add('ok');
        chip.classList.add('ok');
        bg = 'linear-gradient(to right, #065f46, #064e3b)';
        border = '1px solid rgba(34,197,94,0.6)';
    } else if (level === 'warn') {
        dot.classList.add('warn');
        chip.classList.add('warn');
        bg = 'linear-gradient(to right, #92400e, #7c2d12)';
        border = '1px solid rgba(249,115,22,0.6)';
    } else if (level === 'err') {
        dot.classList.add('err');
        chip.classList.add('err');
        bg = 'linear-gradient(to right, #7f1d1d, #450a0a)';
        border = '1px solid rgba(239,68,68,0.7)';
    }

    banner.style.background = bg;
    banner.style.borderBottom = border;
}

function updateDashboard(data) {
    document.getElementById('statusLabel').textContent = data.status_label || 'NO DATA';
    document.getElementById('statusHeadline').textContent = data.status_headline || 'No status available';
    document.getElementById('lastSync').textContent = data.last_sync || '--';
    document.getElementById('lastRestart').textContent = data.last_restart || '--';

    if (data.last_file_download && data.last_file_download.time) {
        const dl = data.last_file_download;
        const src = dl.source || 'frame_sync.sh';
        document.getElementById('lastDownload').textContent =
            dl.time + ' (' + src + ')';
    } else {
        document.getElementById('lastDownload').textContent = '--';
    }

    document.getElementById('currentRemote').textContent = data.current_remote || '--';
    document.getElementById('remoteCount').textContent = (data.google_count != null ? data.google_count : '--');
    document.getElementById('localCount').textContent = (data.local_count != null ? data.local_count : '--');

    document.getElementById('webStatusLabel').textContent = data.web_status_label || '--';
    document.getElementById('pfStatusLabel').textContent = data.pf_status_label || '--';

    const webDot = document.getElementById('webStatusDot');
    const pfDot = document.getElementById('pfStatusDot');
    webDot.classList.remove('ok', 'warn', 'err');
    pfDot.classList.remove('ok', 'warn', 'err');

    if (data.web_status_level) {
        webDot.classList.add(data.web_status_level);
    }
    if (data.pf_status_level) {
        pfDot.classList.add(data.pf_status_level);
    }

    if (data.generated_at) {
        document.getElementById('generatedAt').textContent = data.generated_at;
    }

    applyStatusLights(data.level || 'err');

    const logOut = document.getElementById('logOutput');
    if (data.log_tail) {
        logOut.textContent = data.log_tail;
    } else {
        logOut.textContent = '(log is empty or missing)';
    }
}

function fetchStatus() {
    return fetch('/api/status')
        .then(r => r.json())
        .then(data => {
            updateDashboard(data);
        })
        .catch(err => {
            console.error('Error fetching status:', err);
        });
}

function runCheck() {
    const btn = document.getElementById('btnRunCheck');
    btn.disabled = true;
    btn.textContent = 'Running chk_sync.sh --d…';

    fetch('/api/run-check', { method: 'POST' })
        .then(r => r.json())
        .then(data => {
            const out = [];
            out.push('# chk_sync.sh --d run');
            out.push('Exit code: ' + data.exit_code);

            if (data.stdout) {
                out.push('');
                out.push('STDOUT:');
                out.push(data.stdout);
            }
            if (data.stderr) {
                out.push('');
                out.push('STDERR:');
                out.push(data.stderr);
            }

            document.getElementById('logOutput').textContent = out.join('\n');
        })
        .catch(err => {
            console.error('Error running chk_sync.sh:', err);
            document.getElementById('logOutput').textContent =
                'Error running chk_sync.sh --d: ' + err;
        })
        .finally(() => {
            btn.disabled = false;
            btn.textContent = '▶ Run chk_sync.sh --d';
            // Refresh status afterward
            fetchStatus();
        });
}

document.addEventListener('DOMContentLoaded', () => {
    fetchStatus();
    setInterval(fetchStatus, 30000);
    document.getElementById('btnRunCheck').addEventListener('click', runCheck);
});
