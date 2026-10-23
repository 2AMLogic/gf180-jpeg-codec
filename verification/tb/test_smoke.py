"""Skeleton bench: proves the vendored runner builds, runs and reports a
verdict on both simulators. Replaced by real codec benches in later issues."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


@cocotb.test()
async def test_increment(dut):
    """dout is din + 1, registered. Fails under +define+INJECT_BUG_ENV."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for value in (0, 1, 0x7F, 0xFE, 0xFF):
        dut.din.value = value
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        assert int(dut.dout.value) == (value + 1) & 0xFF, (
            f"din={value:#04x} dout={int(dut.dout.value):#04x}"
        )
