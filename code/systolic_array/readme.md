
# Systolic Array — Component Documentation

**Scope:** `dff.sv`, `d_ff_chain.sv`, `processing_element.sv`, `pe_array.sv`, `systolic.sv`, `tb_systolic_array.sv`
**Function:** 4×4 fixed-point matrix multiplier, `Y = A × B`, computed via a weight-stationary, activation-streaming 2D systolic array.

---

## 1. Architecture Overview

This is a classic 2D systolic MAC array:

- **B (weights)** is *stationary* — held fixed in each PE for the entire computation, read straight off the `B` input port (not clocked in ahead of time; see §5 caveat).
- **A (activations)** *streams* into the array from the left edge, one diagonal per cycle, skewed in time so each row enters one cycle later than the row above it.
- **Partial sums** flow *vertically*, top to bottom, accumulating one MAC per row as they pass through.
- Because the inputs are skewed on the way in, the outputs emerge skewed on the way out and must be **un-skewed** before they represent a valid row of the result matrix — this is the role of the second set of `d_ff_chain` instances.

Total latency for an `N×N` array: `3N - 1` cycles from `start` to the last valid output row, i.e. **11 cycles for N=4**.

```
        A (streamed in, skewed by row)
              │
   ┌──────────▼──────────┐
   │   PE   PE   PE   PE  │ ← row 0 (no input delay)
   │   PE   PE   PE   PE  │ ← row 1 (1-cycle input delay)
   │   PE   PE   PE   PE  │ ← row 2 (2-cycle input delay)
   │   PE   PE   PE   PE  │ ← row 3 (3-cycle input delay)
   └──────────┬──────────┘
              │
     psum flows top→bottom, out the bottom row
     (then un-skewed on the way to OUT[][])
```

---

## 2. Module: `dff.sv`

Single register with synchronous enable and **asynchronous, active-high** reset.

```systemverilog
always_ff @(posedge clk or posedge rst)
  if (rst) dout <= '0;
  else if (en) dout <= din;
```

- `DATA_WIDTH` parameterized, default 4.
- Note the reset convention: **active-high, `posedge rst`**. This is the opposite polarity/edge convention used elsewhere in the project (`dma.sv`, `async_fifo.sv`, `input_buffer.sv` all use active-low `rst_n` with `negedge` assertion). Any block that bridges between the systolic core and those modules needs an explicit inversion — flagged again in §6.

## 3. Module: `d_ff_chain.sv`

Chains `DEPTH` instances of `dff` to realize a pure delay line of `DEPTH` cycles.

- `DEPTH = 0` is **not represented** in the array (`data_wire[0:DEPTH]`, loop runs while `i < DEPTH`) — if `DEPTH == 0` the generate block produces zero instances and `dout` is combinationally tied to `din` via `data_wire[0] = din` / `dout = data_wire[DEPTH]` collapsing to the same wire. This is used correctly in `pe_array.sv`, which only instantiates chains for `k = 1 .. MATRIX_SIZE-1` and wires row 0 straight through without a chain at all.
- Used twice in `pe_array.sv`: once to skew **inputs** (per-row delay before entering column 0), once to un-skew **outputs** (per-column delay after leaving the bottom row).

## 4. Module: `processing_element.sv`

The MAC cell. Per cycle, when `pe_en`:

```systemverilog
psum_out <= psum_in + (weight * in);
a_out    <= in;
```

- `in`/`a_out`: horizontal activation pass-through, registered (1-cycle pipeline per column).
- `weight`: **combinational** input from `B[r][c]`, not registered inside the PE — see §5.
- `psum_in`/`psum_out`: vertical partial-sum pass-through, registered.
- Async active-high reset clears both outputs to 0.
- There's a commented-out alternate implementation above the active code (`weight_reg`/`a_reg` block) that appears to be an earlier draft with separate weight-stationary registration — currently dead code, safe to delete once the design is confirmed stable, but worth deciding rather than leaving as clutter.

## 5. Module: `pe_array.sv`

Wires up an `MATRIX_SIZE × MATRIX_SIZE` grid of `processing_element`s plus the control counter and skew/unskew chains.

**Control:**
- `counter` runs `0 → 3N-2` while `running` (or on the `start` cycle), then wraps to 0.
- `running` is set on `start`, cleared when `counter` reaches `3N-1`.
- `pe_en = running || start` — gates every PE and every skew-chain register.

**Input path:**
- `A` is transposed into `A_transposed` so that `A_transposed[row][counter]` streams column `counter` of the original `A` into `data_in_A[row]` — i.e., column-by-column of `A`, one column per cycle, for cycles `0..N-1`.
- Row 0 skew = 0 cycles; row `k` skew = `k` cycles (`d_ff_chain` `DEPTH=k`).
- **Caveat:** `B` is *not* skewed or streamed at all — `weight = B[r][c]` is presented to every PE **combinationally, for the entire duration** of the computation, straight off the top-level `B` port. This means the testbench (and any real caller) must hold `A` and `B` stable on the input bus for the full `3N-1` cycles of the run, not just pulse them in at `start`. This works in `tb_systolic_array.sv` because `input_data` is a static register held for the whole run — but it's a real constraint on any caller (e.g. `systolic_adapter`, which does hold `sys_input_data` in a register — confirmed compatible) and worth documenting explicitly since it's easy to violate if a future block tries to double-buffer inputs mid-computation.

**Output path:**
- Bottom-row `psum_wire[N][col]` is un-skewed with `DEPTH = N-1-col` (column `N-1` gets 0 delay, column 0 gets the most delay) — mirror image of the input skew, which is correct for realigning a diagonal wavefront back into a single row.
- Output sampling window: `counter` in `[2N-1, 3N-2]` — during this window, `OUT[counter - (2N-1)][:]` is written each cycle, so all `N` rows of the result land over `N` consecutive cycles.
- `valid` is a **single-cycle pulse** at `counter == 3N-1` (one cycle *after* the last output row is written, not during it).

**Something to double check before sign-off:** with `valid` pulsing the cycle *after* row `N-1` is written, and `systolic_adapter` capturing `sys_output_data` (i.e. the full `OUT` array) only once, on the falling edge of `sys_valid` — this depends on `OUT` still holding its final value one cycle after the write completes, which it does (registers hold state), so this is fine, but it's a one-cycle margin, not a wide window. Worth a directed testbench check that `valid` timing doesn't shift if `MATRIX_SIZE` changes (formula is parametric, so it should scale, but hasn't been tested at any size other than 4).

## 6. Module: `systolic.sv`

Thin flattening wrapper: unpacks `input_data` (big-endian, `A` in upper half, `B` in lower half) into 2D arrays for `pe_array`, and repacks `arr_mat_out` into flat `output_data`.

- Reset here is still **active-high** (`rst`, `posedge`), consistent with `pe_array`/`processing_element`/`dff` — this module itself has no CDC or polarity concerns; they only appear at its port boundary when something upstream (e.g. `dma_systolic_bridge`, using active-low `rst_sys_n`) connects to it. **Action item carried over from the integration review:** whatever top-level module instantiates `systolic` needs to invert reset polarity at that boundary (`~rst_sys_n` → `rst`).
- Bit-packing convention (`(LIN_SIZE-1) - (i*MATRIX_SIZE+j)*DATA_WIDTH -: DATA_WIDTH`) is consistent between the two `always_comb` unpack blocks and the repack block — matrix element `[i][j]` always maps to the same nibble position on both ends, so this module is internally self-consistent. `tb_systolic_array.sv`'s packing code duplicates this exact indexing by hand rather than calling a shared function; low risk since it currently matches, but a shared pack/unpack function (or bind-based DPI) would remove the duplication and the risk of the two copies drifting apart later.

## 7. Module: `tb_systolic_array.sv`

Directed (non-self-checking) testbench:
- Loads `A` with values `(i+j)%3 + 1`, `B` as a 4×4 identity matrix — so expected `Y = A` exactly, which makes the test easy to eyeball but does **not exercise actual multiply-accumulate with non-trivial weights** (every product is `×1` or `×0`). It confirms data routing/skew/timing but not arithmetic correctness of the MAC itself.
- Purely `$display`-based — no automated pass/fail, no assertions, relies on a human reading printed matrices.
- Single `start` pulse, single computation, no repeated/back-to-back runs — doesn't test whether the array can immediately accept a new `start` right after `running` clears, or whether `B`/`A` changing mid-run (a caller mistake) causes silently wrong output rather than a flagged error.

**Recommended before integration sign-off** (flagging, not doing yet — let me know if you want these written):
1. Self-checking version with a `$display`-free assertion-based scoreboard, so it can run headless.
2. A test case with non-trivial `B` (not identity) to actually validate the MAC math against a reference model.
3. Back-to-back `start` pulses to confirm the array is re-triggerable without an intervening reset.

---

## Summary Table

| Module | Reset style | Purely combinational? | Notable constraint |
|---|---|---|---|
| `dff` | async, active-high | No | — |
| `d_ff_chain` | async, active-high (inherited) | No | `DEPTH=0` collapses to wire, used intentionally for row 0 |
| `processing_element` | async, active-high | No (registered MAC) | `weight` port is combinational, not latched |
| `pe_array` | async, active-high | No | `A`/`B` must stay stable for full `3N-1` cycles |
| `systolic` | async, active-high | Yes (wrapper only) | Reset polarity must be inverted at any active-low boundary |
| `tb_systolic_array` | n/a | n/a | Directed only, identity-weight test, no self-checking |

---

*Next up: `input_buffer_if`/`output_buffer_if`, `async_fifo`, and the `dma_if_signals`/`systolic_if` bridge — let me know when you want those written up.*
