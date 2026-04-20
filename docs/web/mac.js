// OCP MXFP8 MAC Generator Controller

let twin = null;
let currentCycle = 0;
let simulationState = "IDLE"; // IDLE, RUNNING, COMPLETED
let elements = [];
let outputResult = 0n;

function log(msg) {
    const output = document.getElementById('log-output');
    if (output) {
        output.textContent += msg + "\n";
        const consoleElem = document.getElementById('console');
        if (consoleElem) {
            consoleElem.scrollTop = consoleElem.scrollHeight;
        }
    }
}

// --- Numerical Decoders (reused from main.js) ---

function decode_e2m1(bits) {
    const s = (bits >> 3) & 1;
    const e = (bits >> 1) & 3;
    const m = bits & 1;
    if (e === 0) return (s ? -1 : 1) * (m / 2.0);
    return (s ? -1 : 1) * Math.pow(2, e - 1) * (1 + m / 2.0);
}

function decode_e3m2(bits) {
    const s = (bits >> 5) & 1;
    const e = (bits >> 2) & 7;
    const m = bits & 3;
    if (e === 0) return (s ? -1 : 1) * Math.pow(2, -2) * (m / 4.0);
    return (s ? -1 : 1) * Math.pow(2, e - 3) * (1 + m / 4.0);
}

function decode_e2m3(bits) {
    const s = (bits >> 5) & 1;
    const e = (bits >> 3) & 3;
    const m = bits & 7;
    if (e === 0) return (s ? -1 : 1) * (m / 8.0);
    return (s ? -1 : 1) * Math.pow(2, e - 1) * (1 + m / 8.0);
}

function decode_e4m3(bits) {
    if (bits === 0x7F || bits === 0xFF) return NaN;
    const s = (bits >> 7) & 1;
    const e = (bits >> 3) & 0xF;
    const m = bits & 7;
    if (e === 0) return (s ? -1 : 1) * Math.pow(2, -6) * (m / 8.0);
    return (s ? -1 : 1) * Math.pow(2, e - 7) * (1 + m / 8.0);
}

function decode_e5m2(bits) {
    const s = (bits >> 7) & 1;
    const e = (bits >> 2) & 0x1F;
    const m = bits & 3;
    if (e === 0x1F) return m === 0 ? (s ? -Infinity : Infinity) : NaN;
    if (e === 0) return (s ? -1 : 1) * Math.pow(2, -14) * (m / 4.0);
    return (s ? -1 : 1) * Math.pow(2, e - 15) * (1 + m / 4.0);
}

function decode_int8(bits) {
    let val = bits >= 128 ? bits - 256 : bits;
    return val / 64.0;
}

function decode_int8_sym(bits) {
    if (bits === 0x80) return NaN;
    let val = bits >= 128 ? bits - 256 : bits;
    return val / 64.0;
}

function decode_ue8m0(bits) {
    if (bits === 0xFF) return NaN;
    return Math.pow(2, bits - 127);
}

function decode(bits, format) {
    switch(parseInt(format)) {
        case 0: return decode_e4m3(bits);
        case 1: return decode_e5m2(bits);
        case 2: return decode_e3m2(bits);
        case 3: return decode_e2m3(bits);
        case 4: return decode_e2m1(bits);
        case 5: return decode_int8(bits);
        case 6: return decode_int8_sym(bits);
        default: return 0;
    }
}

// --- App Logic ---

function initApp() {
    try {
        log("Instantiating Digital Twin...");
        if (typeof Module.DigitalTwin === 'undefined') {
            throw new Error("DigitalTwin class not found in WASM Module. Check if WASM is loaded correctly.");
        }
        twin = new Module.DigitalTwin();
        resetSimulation();
        randomizeElements();
        setupEventListeners();
        log("Ready.");
    } catch (e) {
        log("ERROR: " + e.message);
        console.error(e);
    }
}

function randomizeElements() {
    elements = [];
    const fmtA = document.getElementById('format-a').value;
    const fmtB = document.getElementById('format-b').value;
    const scaleAHex = parseInt(document.getElementById('scale-a').value, 16) || 0x7F;
    const scaleBHex = parseInt(document.getElementById('scale-b').value, 16) || 0x7F;
    const scaleA = decode_ue8m0(scaleAHex);
    const scaleB = decode_ue8m0(scaleBHex);

    const body = document.getElementById('elements-body');
    body.innerHTML = '';

    for (let i = 0; i < 32; i++) {
        let aHex, bHex;
        if (fmtA == '0' || fmtA == '1' || fmtA == '5' || fmtA == '6') aHex = Math.floor(Math.random() * 256);
        else if (fmtA == '2' || fmtA == '3') aHex = Math.floor(Math.random() * 64);
        else aHex = Math.floor(Math.random() * 16);

        if (fmtB == '0' || fmtB == '1' || fmtB == '5' || fmtB == '6') bHex = Math.floor(Math.random() * 256);
        else if (fmtB == '2' || fmtB == '3') bHex = Math.floor(Math.random() * 64);
        else bHex = Math.floor(Math.random() * 16);

        elements.push({a: aHex, b: bHex});

        const aDec = decode(aHex, fmtA) * scaleA;
        const bDec = decode(bHex, fmtB) * scaleB;
        const prod = aDec * bDec;

        const row = document.createElement('tr');
        row.id = `row-${i}`;
        row.innerHTML = `
            <td>${i}</td>
            <td>0x${aHex.toString(16).padStart(2, '0').toUpperCase()}</td>
            <td>${aDec.toExponential(2)}</td>
            <td>0x${bHex.toString(16).padStart(2, '0').toUpperCase()}</td>
            <td>${bDec.toExponential(2)}</td>
            <td>${prod.toExponential(2)}</td>
        `;
        body.appendChild(row);
    }
    log("Elements randomized.");
}

function resetSimulation() {
    if (twin) {
        twin.set_rst_n(false);
        twin.step();
        twin.set_rst_n(true);
        twin.set_ena(true);
    }
    currentCycle = 0;
    simulationState = "RUNNING";
    outputResult = 0n;
    updateUI();

    // Clear highlights
    document.querySelectorAll('#elements-body tr').forEach(tr => tr.style.background = 'none');

    document.getElementById('acc-hex').textContent = "0x00000000";
    document.getElementById('acc-dec').textContent = "0.0";
    document.getElementById('status-flags').textContent = "-";

    log("Simulation reset. Ready to start.");
}

function updateUI() {
    document.getElementById('curr-cycle').textContent = currentCycle;
    document.getElementById('status-display').textContent = `Status: ${simulationState} (Cycle ${currentCycle})`;
}

function stepSimulation() {
    if (simulationState === "COMPLETED") {
        log("Simulation already completed. Reset to run again.");
        return;
    }

    let ui_in = 0;
    let uio_in = 0;

    const getVal = (id) => parseInt(document.getElementById(id).value);
    const getHex = (id) => parseInt(document.getElementById(id).value, 16) || 0;

    const isPacked = getVal('packed-mode') === 1;
    const streamLimit = isPacked ? 16 : 32;
    const captureCycle = streamLimit + 4;
    const lastCycle = captureCycle + 4;

    if (currentCycle === 0) {
        // Metadata
        ui_in = (getVal('lns-mode') << 3) | (getVal('nbm-offset-a'));
        uio_in = (getVal('mx-plus-en') << 7) | (getVal('packed-mode') << 6) | (getVal('overflow-mode') << 5) | (getVal('rounding-mode') << 3) | (getVal('nbm-offset-b'));
        log(`Cycle 0: Metadata ui=0x${ui_in.toString(16)}, uio=0x${uio_in.toString(16)}`);
    } else if (currentCycle === 1) {
        // Config A
        ui_in = getHex('scale-a');
        uio_in = (getVal('bm-index-a') << 3) | getVal('format-a');
        log(`Cycle 1: Config A ui=0x${ui_in.toString(16)}, uio=0x${uio_in.toString(16)}`);
    } else if (currentCycle === 2) {
        // Config B
        ui_in = getHex('scale-b');
        uio_in = (getVal('bm-index-b') << 3) | getVal('format-b');
        log(`Cycle 2: Config B ui=0x${ui_in.toString(16)}, uio=0x${uio_in.toString(16)}`);
    } else if (currentCycle >= 3 && currentCycle < 3 + streamLimit) {
        // Streaming
        const idx = currentCycle - 3;
        ui_in = elements[idx].a;
        uio_in = elements[idx].b;

        // Highlight current row
        document.querySelectorAll('#elements-body tr').forEach(tr => tr.style.background = 'none');
        const row = document.getElementById(`row-${idx}`);
        if (row) {
            row.style.background = '#d1ecf1';
            row.scrollIntoView({behavior: 'smooth', block: 'center'});
        }
    } else if (currentCycle >= 3 + streamLimit && currentCycle < captureCycle + 1) {
        ui_in = 0;
        uio_in = 0;
        log(`Cycle ${currentCycle}: Flushing/Scaling...`);
    } else if (currentCycle > captureCycle && currentCycle <= lastCycle) {
        ui_in = 0;
        uio_in = 0;
        const byte = BigInt(twin.get_uo_out());
        outputResult = (outputResult << 8n) | byte;
        log(`Cycle ${currentCycle}: Output byte 0x${byte.toString(16).padStart(2, '0')}`);

        if (currentCycle === lastCycle) {
            simulationState = "COMPLETED";
            finalizeResult();
        }
    }

    twin.set_ui_in(ui_in);
    twin.set_uio_in(uio_in);
    twin.step();

    document.getElementById('curr-ui-in').textContent = `0x${ui_in.toString(16).padStart(2, '0').toUpperCase()}`;
    document.getElementById('curr-uio-in').textContent = `0x${uio_in.toString(16).padStart(2, '0').toUpperCase()}`;

    currentCycle++;
    updateUI();
}

function finalizeResult() {
    let result = outputResult;
    let signedRes = result;
    if (result & 0x80000000n) {
        signedRes = result - 0x100000000n;
    }
    const floatRes = Number(signedRes) / 256.0;

    document.getElementById('acc-hex').textContent = `0x${result.toString(16).padStart(8, '0').toUpperCase()}`;
    document.getElementById('acc-dec').textContent = floatRes.toFixed(4);

    if (result === 0x7FC00000n || result === 0x7F800000n || result === 0xFF800000n) {
        document.getElementById('status-flags').textContent = "Special Value (NaN/Inf) detected";
    } else {
        document.getElementById('status-flags').textContent = "Normal";
    }
    log(`Final Result: ${floatRes}`);
}

function runAll() {
    if (simulationState === "COMPLETED") resetSimulation();
    const isPacked = (parseInt(document.getElementById('packed-mode').value) === 1);
    const lastCycle = isPacked ? 24 : 40;
    while (simulationState !== "COMPLETED" && currentCycle <= lastCycle) {
        stepSimulation();
    }
}

function setupEventListeners() {
    document.getElementById('randomize-btn').addEventListener('click', () => {
        resetSimulation();
        randomizeElements();
    });
    document.getElementById('run-all-btn').addEventListener('click', runAll);
    document.getElementById('step-btn').addEventListener('click', stepSimulation);
    document.getElementById('reset-btn').addEventListener('click', resetSimulation);

    // Auto-reset if formats change
    document.getElementById('format-a').addEventListener('change', () => { resetSimulation(); randomizeElements(); });
    document.getElementById('format-b').addEventListener('change', () => { resetSimulation(); randomizeElements(); });
    document.getElementById('lns-mode').addEventListener('change', resetSimulation);

    document.getElementById('mx-plus-en').addEventListener('change', (e) => {
        document.querySelectorAll('.mx-plus-only').forEach(item => {
            item.classList.toggle('hidden', e.target.value === '0');
        });
        resetSimulation();
    });

    document.querySelectorAll('#scale-a, #scale-b, #bm-index-a, #bm-index-b, #nbm-offset-a, #nbm-offset-b, #rounding-mode, #overflow-mode, #packed-mode').forEach(el => {
        el.addEventListener('change', () => {
            resetSimulation();
            randomizeElements();
        });
    });
}
