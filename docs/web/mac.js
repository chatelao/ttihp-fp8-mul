// OCP MXFP8 MAC Generator Controller

let twin = null;
let currentCycle = 0;
let simulationState = "IDLE"; // IDLE, RUNNING, COMPLETED
let elements = [];
let outputResult = 0n;

let Module = {
    onRuntimeInitialized: function() {
        console.log("WASM Runtime Initialized");
        initApp();
    }
};

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

function decode(bits, format) {
    switch(parseInt(format)) {
        case 0: return decode_e4m3(bits);
        case 1: return decode_e5m2(bits);
        case 2: return decode_e3m2(bits);
        case 3: return decode_e2m3(bits);
        case 4: return decode_e2m1(bits);
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

    const body = document.getElementById('elements-body');
    body.innerHTML = '';

    for (let i = 0; i < 32; i++) {
        let aHex, bHex;
        if (fmtA == '0' || fmtA == '1') aHex = Math.floor(Math.random() * 256);
        else if (fmtA == '2' || fmtA == '3') aHex = Math.floor(Math.random() * 64);
        else aHex = Math.floor(Math.random() * 16);

        if (fmtB == '0' || fmtB == '1') bHex = Math.floor(Math.random() * 256);
        else if (fmtB == '2' || fmtB == '3') bHex = Math.floor(Math.random() * 64);
        else bHex = Math.floor(Math.random() * 16);

        elements.push({a: aHex, b: bHex});

        const aDec = decode(aHex, fmtA);
        const bDec = decode(bHex, fmtB);
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

    if (currentCycle === 0) {
        // Metadata
        const lns = parseInt(document.getElementById('lns-mode').value);
        const rnd = parseInt(document.getElementById('rounding-mode').value);
        ui_in = (lns << 3);
        uio_in = (rnd << 3);
        log(`Cycle 0: Config (LNS=${lns}, RND=${rnd})`);
    } else if (currentCycle === 1) {
        // Config A
        ui_in = 0x7F; // Scale 1.0
        uio_in = parseInt(document.getElementById('format-a').value);
        log(`Cycle 1: Config A (Format=${uio_in})`);
    } else if (currentCycle === 2) {
        // Config B
        ui_in = 0x7F; // Scale 1.0
        uio_in = parseInt(document.getElementById('format-b').value);
        log(`Cycle 2: Config B (Format=${uio_in})`);
    } else if (currentCycle >= 3 && currentCycle <= 34) {
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
    } else if (currentCycle >= 35 && currentCycle <= 36) {
        ui_in = 0;
        uio_in = 0;
        log(`Cycle ${currentCycle}: Flushing...`);
    } else if (currentCycle >= 37 && currentCycle <= 40) {
        ui_in = 0;
        uio_in = 0;
        const byte = BigInt(twin.get_uo_out());
        outputResult = (outputResult << 8n) | byte;
        log(`Cycle ${currentCycle}: Output byte 0x${byte.toString(16).padStart(2, '0')}`);

        if (currentCycle === 40) {
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
    while (simulationState !== "COMPLETED" && currentCycle <= 40) {
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
}
