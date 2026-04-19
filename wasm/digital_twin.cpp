#include <cstdint>
#include <emscripten.h>
#include <emscripten/bind.h>
#include "Vtop.h"
#include "verilated.h"

using namespace emscripten;

class DigitalTwin {
public:
    DigitalTwin() {
        m_top = new Vtop();
    }

    ~DigitalTwin() {
        delete m_top;
    }

    void step() {
        m_top->clk = 0;
        m_top->eval();
        m_top->clk = 1;
        m_top->eval();
    }

    void set_ui_in(uint8_t val) { m_top->ui_in = val; }
    void set_uio_in(uint8_t val) { m_top->uio_in = val; }
    void set_ena(bool val) { m_top->ena = val; }
    void set_rst_n(bool val) { m_top->rst_n = val; }

    uint8_t get_uo_out() { return m_top->uo_out; }
    uint8_t get_uio_out() { return m_top->uio_out; }
    uint8_t get_uio_oe() { return m_top->uio_oe; }

private:
    Vtop* m_top;
};

EMSCRIPTEN_BINDINGS(digital_twin) {
    class_<DigitalTwin>("DigitalTwin")
        .constructor<>()
        .function("step", &DigitalTwin::step)
        .function("set_ui_in", &DigitalTwin::set_ui_in)
        .function("set_uio_in", &DigitalTwin::set_uio_in)
        .function("set_ena", &DigitalTwin::set_ena)
        .function("set_rst_n", &DigitalTwin::set_rst_n)
        .function("get_uo_out", &DigitalTwin::get_uo_out)
        .function("get_uio_out", &DigitalTwin::get_uio_out)
        .function("get_uio_oe", &DigitalTwin::get_uio_oe);
}
