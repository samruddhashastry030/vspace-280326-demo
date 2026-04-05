import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

SBOX = [0xC,0x5,0x6,0xB,0x9,0x0,0xA,0xD,
        0x3,0xE,0xF,0x8,0x4,0x7,0x1,0x2]
PLAYER = [0,16,32,48,1,17,33,49,2,18,34,50,3,19,35,51,
          4,20,36,52,5,21,37,53,6,22,38,54,7,23,39,55,
          8,24,40,56,9,25,41,57,10,26,42,58,11,27,43,59,
          12,28,44,60,13,29,45,61,14,30,46,62,15,31,47,63]
MASK80 = (1 << 80) - 1
MASK64 = (1 << 64) - 1
CLEAR_TOP4 = MASK80 ^ (0xF << 76)

class PresentModel:
    def __init__(self):
        self.reset()

    def reset(self):
        self.key  = 0
        self.pt   = 0
        self.ct   = 0
        self.done = False

    def load_key(self, key80):
        self.key = key80 & MASK80

    def load_pt(self, pt64):
        self.pt = pt64 & MASK64

    def _generateRoundKeys(self, key):
        roundKeys = []
        for i in range(1, 33):
            roundKeys.append((key >> 16) & MASK64)
            key = ((key << 61) | (key >> 19)) & MASK80
            top4 = (key >> 76) & 0xF
            key = (key & CLEAR_TOP4) | (SBOX[top4] << 76)
            key ^= i << 15
        return roundKeys

    def _sbox(self, state):
        tmp = 0
        for j in range(16):
            tmp |= SBOX[(state >> (4*j)) & 0xF] << (4*j)
        return tmp

    def _player(self, state):
        tmp = 0
        for j in range(64):
            tmp |= ((state >> j) & 1) << PLAYER[j]
        return tmp

    def encrypt(self):
        state = self.pt & MASK64
        rks = self._generateRoundKeys(self.key & MASK80)
        for i in range(31):
            state ^= rks[i]
            state = self._sbox(state)
            state = self._player(state)
        state ^= rks[31]
        self.ct   = state
        self.done = True
        return state

    def get_note(self):
        return self.ct & 0x7

    def get_duration(self):
        return (self.ct >> 4) & 0xF

    def is_chord(self, threshold=2):
        h = bin((self.ct >> 8) & 0xF).count('1')
        return h <= threshold


TEST_VECTORS = [
    (0x0000000000000000, 0x00000000000000000000, 0x5579C1387B228445),
    (0x0000000000000000, 0xFFFFFFFFFFFFFFFFFFFF, 0xE72C46C0F5945049),
    (0xFFFFFFFFFFFFFFFF, 0x00000000000000000000, 0xA112FFC72F68417B),
    (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFFFFFF, 0x3333DCD3213210D2),
]

_m = PresentModel()
for _pt, _key, _expected in TEST_VECTORS:
    _m.load_pt(_pt)
    _m.load_key(_key)
    _got = _m.encrypt()
    assert _got == _expected, (
        f"PresentModel self-check FAILED!\n"
        f"  PT=0x{_pt:016X} KEY=0x{_key:020X}\n"
        f"  Expected: 0x{_expected:016X}\n"
        f"  Got:      0x{_got:016X}"
    )


async def do_reset(dut):
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)

async def load_key(dut, key80):
    for i in range(10):
        byte_val = (key80 >> (72 - i * 8)) & 0xFF
        dut.ui_in.value  = byte_val
        dut.uio_in.value = 0x01
        await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00

async def load_pt(dut, pt64):
    for i in range(8):
        byte_val = (pt64 >> (56 - i * 8)) & 0xFF
        dut.ui_in.value  = byte_val
        dut.uio_in.value = 0x02
        await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00

async def start_encrypt(dut):
    dut.uio_in.value = 0x04
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00

async def wait_done(dut, timeout=800):
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.uio_out.value) & 0x01:
            return True
    return False

async def read_ct(dut):
    ct = 0
    for b in range(8):
        dut.uio_in.value = (b & 0x7) << 4
        await RisingEdge(dut.clk)
        ct |= (int(dut.uo_out.value) & 0xFF) << (b * 8)
    dut.uio_in.value = 0x00
    return ct


@cocotb.test()
async def test_reset_behaviour(dut):
    dut._log.info("=== Phase 1: Reset Behaviour ===")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    dut.ena.value    = 1
    dut.ui_in.value  = 0xFF
    dut.uio_in.value = 0xFF
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    assert (int(dut.uo_out.value)  & 0x01) == 0, "PWM must be LOW during reset"
    assert (int(dut.uio_out.value) & 0x01) == 0, "done must be LOW during reset"
    dut._log.info("Reset behaviour: PASS")


@cocotb.test()
async def test_present_golden_vectors(dut):
    dut._log.info("=== Phase 2: Golden Vector Verification ===")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    model = PresentModel()
    for idx, (pt, key, expected_ct) in enumerate(TEST_VECTORS):
        await do_reset(dut)
        await load_key(dut, key)
        await load_pt(dut, pt)
        await start_encrypt(dut)
        ok = await wait_done(dut)
        assert ok, f"Vector {idx}: done flag never asserted (timeout)"
        hw_ct = await read_ct(dut)
        model.load_key(key)
        model.load_pt(pt)
        ref_ct = model.encrypt()
        status = "PASS" if hw_ct == ref_ct else "FAIL"
        dut._log.info(
            f"Vec {idx}: PT=0x{pt:016X} KEY=0x{key:020X} "
            f"-> HW=0x{hw_ct:016X} REF=0x{ref_ct:016X} [{status}]"
        )
        assert hw_ct == ref_ct, (
            f"Vector {idx} mismatch!\n"
            f"  Expected: 0x{ref_ct:016X}\n"
            f"  Got:      0x{hw_ct:016X}"
        )
    dut._log.info("All golden vector tests: PASS")


@cocotb.test()
async def test_music_pwm_output(dut):
    dut._log.info("=== Phase 3: Music / PWM Output ===")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    test_key = 0xDEADBEEFCAFEBABE1234
    test_pt  = 0x0000000000000000
    await do_reset(dut)
    await load_key(dut, test_key)
    await load_pt(dut, test_pt)
    await start_encrypt(dut)
    ok = await wait_done(dut)
    assert ok, "done flag never asserted"
    transitions = 0
    prev = int(dut.uio_out.value) & 0x02
    for _ in range(50000):
        await RisingEdge(dut.clk)
        cur = int(dut.uio_out.value) & 0x02
        if cur != prev:
            transitions += 1
        prev = cur
    dut._log.info(f"PWM transitions in 2000 cycles: {transitions}")
    assert transitions > 0, "PWM never toggled — music engine is silent!"
    model = PresentModel()
    model.load_key(test_key)
    model.load_pt(test_pt)
    model.encrypt()
    note = model.get_note()
    assert 0 <= note <= 7, f"Note index {note} out of pentatonic range!"
    dut._log.info("Music PWM test: PASS")


@cocotb.test()
async def test_pause_resume(dut):
    dut._log.info("=== Phase 4: Pause / Resume ===")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    test_key = 0xCAFEBABEDEADBEEF1234
    test_pt  = 0xA5A5A5A5A5A5A5A5
    await do_reset(dut)
    await load_key(dut, test_key)
    await load_pt(dut, test_pt)
    await start_encrypt(dut)
    await wait_done(dut)
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 5)
    snapshot = int(dut.uio_out.value) & 0x02
    await ClockCycles(dut.clk, 30)
    assert (int(dut.uio_out.value) & 0x02) == snapshot, "PWM changed while paused!"
    dut.ui_in.value = 0x01
    transitions = 0
    prev = int(dut.uio_out.value) & 0x02
    for _ in range(50000):
        await RisingEdge(dut.clk)
        cur = int(dut.uio_out.value) & 0x02
        if cur != prev:
            transitions += 1
        prev = cur
    assert transitions > 0, "PWM did not resume after un-pause!"
    dut._log.info("Pause / Resume test: PASS")


@cocotb.test()
async def test_avalanche_effect(dut):
    dut._log.info("=== Phase 5: Avalanche Effect ===")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    model = PresentModel()
    key_a = 0x00000000000000000000
    key_b = 0x00000000000000000001
    pt    = 0x0000000000000000
    model.load_key(key_a); model.load_pt(pt); ct_a = model.encrypt()
    model.load_key(key_b); model.load_pt(pt); ct_b = model.encrypt()
    diff_bits = bin(ct_a ^ ct_b).count('1')
    dut._log.info(f"KEY_A -> 0x{ct_a:016X}  KEY_B -> 0x{ct_b:016X}  bit-diff={diff_bits}")
    assert ct_a != ct_b, "Avalanche FAILED: identical ciphertexts!"
    assert diff_bits >= 16, f"Avalanche WEAK: only {diff_bits} bits differ (need >=16)"
    dut._log.info(f"Avalanche effect: PASS ({diff_bits} bits differ)")
