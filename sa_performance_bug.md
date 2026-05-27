# FastAPI Lab App Bug: Slow Simulated Annealing + Frozen Polling

Two performance issues made `workover_app.py` appear broken after form submission: the optimization ran for several minutes instead of seconds, and the polling page felt unresponsive during that time.

---

## Bug 1: `copy.deepcopy` in the SA Inner Loop

### Symptom
After uploading CSVs and clicking **Optimize Schedule**, the spinning "Optimizing…" page stayed up for 1–2 minutes.

### Root Cause
The simulated annealing loop called `copy.deepcopy(current)` on every iteration:

```python
for _ in range(n_iter):
    neighbor = copy.deepcopy(current)   # called 200,000 times
```

`copy.deepcopy` uses Python's object introspection machinery — it is correct but extremely slow. With 200,000 iterations, this added tens of seconds to the runtime even though `current` is just a `List[List[int]]` (3 lists of ~7 integers each).

### Fix: Shallow list-of-lists copy

```python
neighbor = [list(r) for r in current]
```

A list comprehension that calls `list()` on each inner list is semantically identical for `List[List[int]]` and is 20–50× faster than `deepcopy`. The same replacement was made where the best solution is saved:

```python
# Before
best = copy.deepcopy(current)

# After
best = [list(r) for r in current]
```

---

## Bug 2: Background Thread Holding the GIL

### Symptom
The polling page (`<meta http-equiv="refresh" content="3">`) sometimes took much longer than 3 seconds to refresh, making the app feel stuck even after the optimization finished.

### Root Cause
Python's Global Interpreter Lock (GIL) is normally released every 5 ms, but a tight CPU-bound loop can hold it for longer between switch points. The SA thread was competing with uvicorn's asyncio event loop (which runs in the main thread) for the GIL. While the thread ran, incoming poll requests could be delayed well beyond 3 seconds.

### Fix: Yield the GIL periodically

```python
if iteration % 1000 == 0:
    time.sleep(0)
```

`time.sleep(0)` releases the GIL immediately and lets the OS scheduler hand control to the event loop. At 200,000 iterations this adds 200 voluntary yields — negligible cost, but enough to keep poll responses snappy.

---

## Files Changed

`session4/data/workover_app.py`:

| Change | Why |
|---|---|
| `copy.deepcopy(current)` → `[list(r) for r in current]` | Fix Bug 1 — 20–50× faster inner loop |
| `copy.deepcopy(current)` → `[list(r) for r in current]` when saving best | Fix Bug 1 — same reason |
| `import time` added | Required for `time.sleep(0)` |
| `time.sleep(0)` every 1,000 iterations | Fix Bug 2 — yields GIL to event loop |
