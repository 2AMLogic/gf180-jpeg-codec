"""Shared configuration-port address map and host driver for the RTL benches.

One copy of the decision 0005 configuration address map
(spec/decision-records/0005-rtl-microarchitecture.md, "Configuration address
map") and the driver for the cfg_*/status_* port set that
rtl/jpeg_codec_top.v and verification/rtl/tb_config_top.v share. The benches
that drive that port (test_config_header.py, test_top_smoke.py,
test_top_golden.py) import from here instead of carrying their own
transcriptions.

This module holds the address map and the port driver only, never an
expected-bytes oracle: the framing and code-construction oracles stay in the
bench that asserts them (test_config_header.py) and in the golden encoder,
written independently of each other and of this file.
"""

from cocotb.triggers import RisingEdge

# Decision 0005 map rows: 0x000 MODE; 0x001/0x002 WIDTH low/high;
# 0x003/0x004 HEIGHT low/high; 0x005 CMD (1 start frame, 2 commit tables,
# 4 clear error).
REG_MODE, REG_W, REG_H, REG_CMD = 0x000, 0x001, 0x003, 0x005

# Decision 0005 table windows, spec sections 5/6 payload bytes in segment
# order: 0x040-0x07F DQT 0 (luma, 64 B zig-zag); 0x080-0x0BF DQT 1 (chroma,
# 64 B); 0x100-0x11B DHT DC 0 (up to 28 B); 0x140-0x1F1 DHT AC 0 (up to
# 178 B); 0x200-0x21B DHT DC 1 (up to 28 B); 0x240-0x2F1 DHT AC 1 (up to
# 178 B).
WIN = {"q0": 0x040, "q1": 0x080, "dc0": 0x100, "ac0": 0x140,
       "dc1": 0x200, "ac1": 0x240}
WIN_LEN = {"q0": 64, "q1": 64, "dc0": 28, "ac0": 178, "dc1": 28, "ac1": 178}


async def wait_idle(dut, cap=60000):
    for _ in range(cap):
        await RisingEdge(dut.clk)
        if dut.status_idle.value == 1:
            return
    raise AssertionError("timeout waiting for idle")


async def cfg_write(dut, addr, val):
    dut.cfg_valid.value = 1
    dut.cfg_addr.value = addr
    dut.cfg_wdata.value = val
    while True:
        await RisingEdge(dut.clk)
        if dut.cfg_ready.value == 1:
            break
    dut.cfg_valid.value = 0


async def write_reg16(dut, addr, v):
    await cfg_write(dut, addr, v & 0xFF)
    await cfg_write(dut, addr + 1, v >> 8)


async def write_table(dut, name, payload):
    assert len(payload) <= WIN_LEN[name]
    for i, b in enumerate(payload):
        await cfg_write(dut, WIN[name] + i, b)


async def configure(dut, mode, w, h):
    await cfg_write(dut, REG_MODE, mode)
    await write_reg16(dut, REG_W, w)
    await write_reg16(dut, REG_H, h)


async def commit(dut):
    await cfg_write(dut, REG_CMD, 2)
    await RisingEdge(dut.clk)
    await wait_idle(dut)
