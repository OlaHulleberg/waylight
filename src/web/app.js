// State
let results = [];
let selectedIndex = 0;

// Get first letter/initial from app name for fallback icon
function getInitial(name) {
    if (!name) return '?';
    return name.charAt(0).toUpperCase();
}

// DOM elements
const searchInput = document.getElementById('search-input');
const resultsContainer = document.getElementById('results-container');
const resultsList = document.getElementById('results-list');
const previewIcon = document.getElementById('preview-icon');
const container = document.querySelector('.container');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    searchInput.focus();

    // Set initial height for animation
    container.style.height = container.offsetHeight + 'px';
});

// Search input handler
searchInput.addEventListener('input', (e) => {
    const query = e.target.value;

    if (query.trim() === '') {
        hideResults();
        return;
    }

    // Send search query to Zig backend
    sendToBackend({
        type: 'search',
        query: query
    });
});

// Keyboard navigation
searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        sendToBackend({ type: 'close' });
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (results.length > 0) {
            selectedIndex = Math.min(selectedIndex + 1, results.length - 1);
            updateSelection();
        }
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (results.length > 0) {
            selectedIndex = Math.max(selectedIndex - 1, 0);
            updateSelection();
        }
    } else if (e.key === 'Enter') {
        e.preventDefault();
        if (results.length > 0 && selectedIndex >= 0) {
            selectResult(results[selectedIndex]);
        }
    }
});

// Update results from backend
function updateResults(newResults) {
    results = newResults;
    selectedIndex = 0;

    if (results.length === 0) {
        hideResults();
        return;
    }

    renderResults();
    showResults();
}

// Render results
function renderResults() {
    resultsList.innerHTML = '';

    // Create sliding selector (single element that moves to selected item)
    const selector = document.createElement('div');
    selector.className = 'selector';
    resultsList.appendChild(selector);

    results.forEach((result, index) => {
        const item = document.createElement('div');
        item.className = 'result-item';
        if (index === selectedIndex) {
            item.classList.add('selected');
        }

        if (result.type === 'calc') {
            item.classList.add('calc-result');
            item.innerHTML = `
                <div class="result-text">
                    <div class="result-description">${result.query} =</div>
                    <div class="result-name">${result.value}</div>
                </div>
                <svg class="copy-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
                </svg>
            `;
        } else {
            const initial = getInitial(result.name);
            item.innerHTML = `
                <div class="result-icon">
                    ${result.icon
                        ? `<img src="${result.icon}" alt="" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex'"><span class="icon-fallback" style="display:none">${initial}</span>`
                        : `<span class="icon-fallback">${initial}</span>`
                    }
                </div>
                <div class="result-text">
                    <div class="result-name">${result.name}</div>
                    ${result.description ? `<div class="result-description">${result.description}</div>` : ''}
                </div>
            `;
        }

        item.addEventListener('click', () => selectResult(result));
        resultsList.appendChild(item);
    });

    // Position selector and preview icon on initial render (after DOM layout)
    requestAnimationFrame(() => {
        updateSelector();
        updatePreviewIcon();
    });
}

// Move selector to selected item
function updateSelector() {
    const selector = resultsList.querySelector('.selector');
    const items = resultsList.querySelectorAll('.result-item');

    if (selector && items[selectedIndex]) {
        const item = items[selectedIndex];
        selector.style.transform = `translateY(${item.offsetTop}px)`;
        selector.style.height = `${item.offsetHeight}px`;
    }
}

// Update preview icon in search bar
function updatePreviewIcon() {
    const selected = results[selectedIndex];

    if (selected && selected.type === 'calc') {
        previewIcon.innerHTML = `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <rect x="4" y="2" width="16" height="20" rx="2"/>
            <line x1="8" y1="6" x2="16" y2="6"/>
            <line x1="8" y1="10" x2="8" y2="10.01"/>
            <line x1="12" y1="10" x2="12" y2="10.01"/>
            <line x1="16" y1="10" x2="16" y2="10.01"/>
            <line x1="8" y1="14" x2="8" y2="14.01"/>
            <line x1="12" y1="14" x2="12" y2="14.01"/>
            <line x1="16" y1="14" x2="16" y2="14.01"/>
            <line x1="8" y1="18" x2="8" y2="18.01"/>
            <line x1="12" y1="18" x2="16" y2="18"/>
        </svg>`;
        previewIcon.classList.add('visible');
    } else if (selected && selected.type === 'app' && selected.icon) {
        previewIcon.innerHTML = `<img src="${selected.icon}" alt="">`;
        previewIcon.classList.add('visible');
    } else {
        previewIcon.innerHTML = '';
        previewIcon.classList.remove('visible');
    }
}

// Update selection
function updateSelection() {
    const items = resultsList.querySelectorAll('.result-item');
    items.forEach((item, index) => {
        if (index === selectedIndex) {
            item.classList.add('selected');
            item.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        } else {
            item.classList.remove('selected');
        }
    });
    updateSelector();
    updatePreviewIcon();
}

// Select a result
function selectResult(result) {
    sendToBackend({
        type: 'select',
        result: result
    });
}

// Animate container height changes (batched to prevent animation interruption)
let heightUpdatePending = false;

function updateContainerHeight() {
    if (heightUpdatePending) return;
    heightUpdatePending = true;

    requestAnimationFrame(() => {
        heightUpdatePending = false;

        const currentHeight = container.offsetHeight;
        container.style.height = 'auto';
        const targetHeight = container.offsetHeight;

        container.style.height = currentHeight + 'px';
        container.offsetHeight; // Force reflow
        container.style.height = targetHeight + 'px';
    });
}

// Show/hide results
function showResults() {
    resultsContainer.classList.remove('hidden');
    updateContainerHeight();
}

function hideResults() {
    resultsContainer.classList.add('hidden');
    previewIcon.innerHTML = '';
    previewIcon.classList.remove('visible');
    updateContainerHeight();
}

// Communication with Zig backend
function sendToBackend(message) {
    // Use WebKit message handler
    if (window.webkit?.messageHandlers?.waylight) {
        window.webkit.messageHandlers.waylight.postMessage(JSON.stringify(message));
    } else {
        console.warn('Backend not available, using mock data');
        // Mock response for testing without backend
        if (message.type === 'search') {
            setTimeout(() => {
                updateResults([
                    { type: 'app', name: 'Firefox', icon: '🌐', description: 'Web Browser' },
                    { type: 'app', name: 'Terminal', icon: '⌨️', description: 'Command Line' },
                    { type: 'app', name: 'Files', icon: '📁', description: 'File Manager' },
                ]);
            }, 50);
        }
    }
}

// Reset UI state (called when window becomes visible)
function resetUI() {
    // Clear search input
    searchInput.value = '';

    // Clear results
    results = [];
    selectedIndex = 0;
    resultsList.innerHTML = '';
    resultsContainer.classList.add('hidden');

    // Clear preview icon
    previewIcon.innerHTML = '';
    previewIcon.classList.remove('visible');

    // Reset container height
    container.style.height = 'auto';
    container.style.height = container.offsetHeight + 'px';

    // Focus search input
    searchInput.focus();
}

// Receive messages from Zig backend
window.receiveFromBackend = function(message) {
    if (message.type === 'results') {
        updateResults(message.results);
    } else if (message.type === 'reset') {
        resetUI();
    }
};
