import schemdraw
import schemdraw.elements as elm
from schemdraw import dsp
import os

# Ensure the output directory exists
os.makedirs('docs/diagrams', exist_ok=True)

with schemdraw.Drawing(file='docs/diagrams/MAC_CORE_SCHEMDRAW.svg') as d:
    d.config(unit=1, fontsize=12)

    # Inputs
    ui = d.add(dsp.Arrow().label('ui_in[7:0]\n(Scale/Elements)', 'left'))
    uio_in = d.add(dsp.Arrow().at((0, -3)).label('uio_in[7:0]\n(Scale/Elements)', 'left'))

    # Control/Config (Using dsp.Box without math characters)
    ctrl = d.add(dsp.Box(w=3.5, h=5).at((2, -1.5)).label('FSM, Config\nand Metadata\nRegisters'))

    # Lane 0
    mul0 = d.add(dsp.Box(w=3, h=1.5).at((7.5, 1)).label('Multiplier\nLane 0'))
    align0 = d.add(dsp.Box(w=3, h=1.5).at((11.5, 1)).label('Aligner\nLane 0'))

    # Lane 1
    mul1 = d.add(dsp.Box(w=3, h=1.5).at((7.5, -3)).label('Multiplier\nLane 1'))
    align1 = d.add(dsp.Box(w=3, h=1.5).at((11.5, -3)).label('Aligner\nLane 1'))

    # Adder
    adder = d.add(dsp.Box(w=3, h=2.5).at((16, -1)).label('32-bit\nAccumulator\nAdder'))

    # Accumulator Register
    acc_reg = d.add(dsp.Box(w=3, h=1.5).at((20.5, -0.5)).label('Accumulator\nRegister'))

    # Sticky/Exception logic
    sticky = d.add(dsp.Box(w=2.5, h=1.5).at((12, -5)).label('Sticky\nExceptions'))

    # Output Mux/Serializer
    ser = d.add(dsp.Box(w=3, h=1.5).at((25, -0.5)).label('Output Mux and\nSerializer'))

    # Output
    out = d.add(dsp.Arrow().at((28, 0.25)).label('uo_out[7:0]', 'right'))

    # Connections
    d.add(dsp.Line().at(ui.end).to(ctrl.W))
    d.add(dsp.Line().at(uio_in.end).to(ctrl.W))

    # Control to Lanes
    d.add(dsp.Arrow().at(ctrl.E).to(mul0.W))
    d.add(dsp.Arrow().at(ctrl.E).to(mul1.W))

    # Lane flow
    d.add(dsp.Arrow().at(mul0.E).to(align0.W))
    d.add(dsp.Arrow().at(mul1.E).to(align1.W))

    d.add(dsp.Arrow().at(align0.E).to(adder.NW))
    d.add(dsp.Arrow().at(align1.E).to(adder.SW))

    # Exception flow
    d.add(dsp.Line().at(mul0.S).to((9, -4.25)))
    d.add(dsp.Arrow().to(sticky.W))
    d.add(dsp.Line().at(sticky.E).to((26.5, -4.25)))
    d.add(dsp.Arrow().to(ser.S))

    # Accumulator flow
    d.add(dsp.Arrow().at(adder.E).to(acc_reg.W))
    d.add(dsp.Arrow().at(acc_reg.E).to(ser.W))
    d.add(dsp.Arrow().at(ser.E).to(out.start))

    # Feedback (Accumulator)
    d.add(dsp.Line().at(acc_reg.S).to((22, -2)))
    d.add(dsp.Line().to((17.5, -2)))
    d.add(dsp.Arrow().to(adder.S))

    # Shared Scaling Feedback to Aligner
    d.add(dsp.Line().at(acc_reg.N).to((22, 4.5)))
    d.add(dsp.Line().to((13, 4.5)))
    d.add(dsp.Arrow().to(align0.N))

    # Labels for clarity
    d.add(elm.Label().at((13, 4.5)).label('Shared Scaling Path', 'top'))
    d.add(elm.Label().at((17.5, -2)).label('Feedback', 'bottom'))
