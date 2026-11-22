// OCP MXFP8 Digital Twin Main Controller

let twin = null;

function log(msg) {
    const output = document.getElementById('log-output');
    output.textContent += msg + "\n";
    document.getElementById('console').scrollTop = document.getElementById('console').scrollHeight;
}

// --- Numerical Decoders ---

function decode_e2m1(bits) {
    const s = (bits >> 3) & 1;
    const e = (bits >> 1) & 3;
    const m = bits & 1;
    if (e === 0) return (s ? -1 : 1) * (m / 2.0); // Subnormal
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
    // Standard 2's complement, but OCP MX specifies it's scaled by 2^-6
    let val = bits >= 128 ? bits - 256 : bits;
    return val / 64.0;
}

function decode_int8_sym(bits) {
    // Symmetric INT8: -127 to 127, 0x80 clamped to -127
    if (bits === 0x80) return -127 / 64.0;
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

// --- UI Logic ---

function initApp() {
    log("Instantiating Digital Twin...");
    twin = new Module.DigitalTwin();

    populateTable();
    setupEventListeners();
    updateDecValues();
    log("Ready.");
}

function populateTable() {
    const body = document.getElementById('elements-body');
    for (let i = 0; i < 32; i++) {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${i}</td>
            <td><input type="text" class="cell-a-hex" data-idx="${i}" value="38" maxlength="2"></td>
            <td><span class="cell-a-dec">-</span></td>
            <td><input type="text" class="cell-b-hex" data-idx="${i}" value="38" maxlength="2"></td>
            <td><span class="cell-b-dec">-</span></td>
            <td><span class="cell-prod">-</span></td>
        `;
        body.appendChild(row);
    }
}

function updateDecValues() {
    const fmtA = document.getElementById('format-a').value;
    const fmtB = document.getElementById('format-b').value;
    const scaleAHex = parseInt(document.getElementById('scale-a').value, 16) || 0;
    const scaleBHex = parseInt(document.getElementById('scale-b').value, 16) || 0;

    const scaleA = decode_ue8m0(scaleAHex);
    const scaleB = decode_ue8m0(scaleBHex);

    document.getElementById('scale-a-dec').textContent = isNaN(scaleA) ? "NaN" : scaleA.toExponential(2);
    document.getElementById('scale-b-dec').textContent = isNaN(scaleB) ? "NaN" : scaleB.toExponential(2);

    const rows = document.querySelectorAll('#elements-body tr');
    rows.forEach((row, i) => {
        const aHex = parseInt(row.querySelector('.cell-a-hex').value, 16) || 0;
        const bHex = parseInt(row.querySelector('.cell-b-hex').value, 16) || 0;

        const aDec = decode(aHex, fmtA);
        const bDec = decode(bHex, fmtB);

        row.querySelector('.cell-a-dec').textContent = isNaN(aDec) ? "NaN" : (aDec * scaleA).toExponential(2);
        row.querySelector('.cell-b-dec').textContent = isNaN(bDec) ? "NaN" : (bDec * scaleB).toExponential(2);

        const prod = (aDec * scaleA) * (bDec * scaleB);
        row.querySelector('.cell-prod').textContent = isNaN(prod) ? "NaN" : prod.toExponential(2);
    });
}

function setupEventListeners() {
    document.querySelectorAll('select, input').forEach(el => {
        el.addEventListener('change', () => {
            if (el.id === 'mx-plus-en') {
                document.querySelectorAll('.mx-plus-only').forEach(item => {
                    item.classList.toggle('hidden', el.value === '0');
                });
            }
            updateDecValues();
        });
    });

    document.getElementById('run-simulation').addEventListener('click', runSimulation);
}

// --- Simulation Driver ---

async function runSimulation() {
    if (!twin) return;
    log("Starting simulation cycle...");

    const getVal = (id) => parseInt(document.getElementById(id).value);
    const getHex = (id) => parseInt(document.getElementById(id).value, 16) || 0;
    const isChecked = (id) => {
        const el = document.getElementById(id);
        return el ? (el.type === 'checkbox' ? el.checked : el.value === '1') : false;
    };

    const isShort = isChecked('short-protocol');
    const isFloat32 = !document.getElementById('output-format') || getVal('output-format') === 1;
    const fmtA = getVal('format-a');
    const fmtB = getVal('format-b');
    const isPacked = (getVal('packed-mode') === 1) && (fmtA === 4) && (fmtB === 4);

    // Reset unless Short Protocol is reusing previously loaded scales
    if (!isShort) {
        twin.set_rst_n(false);
        twin.step();
        twin.set_rst_n(true);
    }
    twin.set_ena(true);

    // Cycle 0: Metadata
    let ui0 = (getVal('lns-mode') << 3) | (getVal('nbm-offset-a'));
    if (isFloat32) ui0 |= 0x20;
    if (isShort) ui0 |= 0x80;
    const uioLow = isShort ? (fmtA & 0x07) : (getVal('nbm-offset-b') & 0x07);
    const uio0 = (getVal('mx-plus-en') << 7) | (getVal('packed-mode') << 6) | (getVal('overflow-mode') << 5) | (getVal('rounding-mode') << 3) | uioLow;

    twin.set_ui_in(ui0);
    twin.set_uio_in(uio0);
    twin.step();
    log(`Cycle 0: ui=0x${ui0.toString(16).padStart(2, '0')}, uio=0x${uio0.toString(16).padStart(2, '0')}`);

    if (!isShort) {
        // Cycle 1: Scale A / Config A
        const ui1 = getHex('scale-a');
        const uio1 = (getVal('bm-index-a') << 3) | fmtA;
        twin.set_ui_in(ui1);
        twin.set_uio_in(uio1);
        twin.step();
        log(`Cycle 1: ui=0x${ui1.toString(16).padStart(2, '0')}, uio=0x${uio1.toString(16).padStart(2, '0')}`);

        // Cycle 2: Scale B / Config B
        const ui2 = getHex('scale-b');
        const uio2 = (getVal('bm-index-b') << 3) | fmtB;
        twin.set_ui_in(ui2);
        twin.set_uio_in(uio2);
        twin.step();
        log(`Cycle 2: ui=0x${ui2.toString(16).padStart(2, '0')}, uio=0x${uio2.toString(16).padStart(2, '0')}`);
    } else {
        log("Short Protocol enabled: skipping config cycles 1-2");
    }

    // Cycles 3-34 (Standard) or 3-18 (Packed): Streaming
    const streamLimit = isPacked ? 16 : 32;
    const rows = document.querySelectorAll('#elements-body tr');
    for (let i = 0; i < streamLimit; i++) {
        const aHex = parseInt(rows[i].querySelector('.cell-a-hex').value, 16) || 0;
        const bHex = parseInt(rows[i].querySelector('.cell-b-hex').value, 16) || 0;
        twin.set_ui_in(aHex);
        twin.set_uio_in(bHex);
        twin.step();
    }
    log(`Streaming completed (${streamLimit} cycles).`);

    // Flush and scaling cycles (2 cycles)
    twin.set_ui_in(0);
    twin.set_uio_in(0);
    twin.step();
    twin.step();
    log("Flush and scaling completed.");

    // Read Result: 4 bytes (read uo_out BEFORE stepping to the next cycle)
    let result = 0n;
    const captureCycle = streamLimit + (isShort ? 2 : 4);
    for (let i = 0; i < 4; i++) {
        const byte = BigInt(twin.get_uo_out());
        result = (result << 8n) | byte;
        log(`Cycle ${captureCycle + 1 + i}: Output byte = 0x${byte.toString(16).padStart(2, '0')}`);
        twin.step();
    }

    const bits = result & 0xFFFFFFFFn;
    document.getElementById('acc-hex').textContent = `0x${bits.toString(16).padStart(8, '0').toUpperCase()}`;

    if (isFloat32) {
        const buffer = new ArrayBuffer(4);
        const view = new DataView(buffer);
        view.setUint32(0, Number(bits), false);
        const floatRes = view.getFloat32(0, false);

        const sign = (bits >> 31n) & 1n;
        const exp = (bits >> 23n) & 0xFFn;
        const mant = bits & 0x7FFFFFn;
        const binStr = `${sign} | ${exp.toString(2).padStart(8, '0')} | ${mant.toString(2).padStart(23, '0')}`;

        document.getElementById('acc-dec').textContent = floatRes.toExponential(4);
        document.getElementById('acc-bin').textContent = binStr;

        if (isNaN(floatRes)) {
            document.getElementById('status-flags').textContent = "NaN (Not a Number)";
        } else if (!isFinite(floatRes)) {
            document.getElementById('status-flags').textContent = "Infinity";
        } else {
            document.getElementById('status-flags').textContent = "Normal (Float32)";
        }
        log(`Final Result (Float32): ${floatRes} (Bits: ${binStr})`);
    } else {
        const signedInt = Number(bits >= 0x80000000n ? bits - 0x100000000n : bits);
        const fixedVal = signedInt / 256.0;
        const binStr = bits.toString(2).padStart(32, '0');
        document.getElementById('acc-dec').textContent = fixedVal.toFixed(6);
        document.getElementById('acc-bin').textContent = binStr;
        document.getElementById('status-flags').textContent = "Fixed-Point S23.8";
        log(`Final Result (S23.8): ${fixedVal} (Raw: ${signedInt})`);
    }
}
