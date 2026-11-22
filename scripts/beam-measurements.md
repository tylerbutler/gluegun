# BEAM candidate measurements

This is the measurement-only deliverable for
[#103](https://github.com/tylerbutler/gluegun/issues/103). It changes no
production behavior. Use the results to plan further measurements before
changing cancellation, response monitors, or TLS trust handling.

## Run

Install and activate the tools in `.mise.toml`, then run from the repository
root:

```sh
just measure-beam
just measure-beam > beam-measurements.txt
```

The recipe builds the locked dependencies and test helpers. The escript uses
`-mode(compile)` and loads `build/dev/erlang/*/ebin`. It prints the runtime,
loaded dependency versions, BEAM paths and module hashes with its raw records.
Keep those records with your results. Do not compare runs with different
dependencies as if they measured the same code.

The harness uses loopback HTTP and TLS peers. It checks complete bodies,
message counts, unrelated mailbox entries, promised-stream cleanup, malformed
headers, and owned process/socket/monitor cleanup. A failed check exits with a
nonzero status. The TLS peer uses generated test credentials in memory.

The suite guard allows 90 seconds after application startup. Script receives,
peer gates, accepts, connection setup, TLS handshakes, and teardown waits each
allow 3 seconds. The suspended processing barrier allows 100 milliseconds;
the resumed barrier allows 3 seconds. A guard worker bounds Gun's underlying
5-second call and terminates on timeout. Existing regression helpers have
their own deadlines within the suite guard. Compilation and application
startup precede that guard.

Raw output uses one prefix and one Erlang map term per line. `sample` records
contain elapsed microseconds, caller reductions, GC counters, and summarized
output; `memory` records contain heap words, memory bytes, mailbox length,
monitors, and binary-reference counts/bytes/refcount histograms. `ca` records
contain decoded/external sizes. Body summaries include byte length and SHA-256.
The script does not dump certificate bytes. The final `result` record checks
zero remaining owned network ports and monitors.

## Workloads and interpretation

### Cancellation

The immediate case drains the caller mailbox before the local peer sends a
real delayed body. It checks that the delayed message can still arrive. The
barrier case suspends Gun, queues a real body, cancels, and attempts a bounded
processing barrier. It resumes Gun, checks the processing barrier, and drains
the queued body. Suspension models a process that cannot handle setup work; it
does not reproduce a particular DNS or TLS failure.

Existing regressions check the late-after-drain contract and promised-stream
discovery before headers, during body collection, and on malformed pushes.
The harness also runs existing local delayed-response fixtures.

A processed cancel and a drained mailbox do not establish socket flow
recovery. Gun can keep HTTP/1.1 reads paused after finite flow credit runs out.
[#78](https://github.com/tylerbutler/gluegun/issues/78) owns that limitation.
This harness adds no negative-credit/custom-handler fixture or production fix.

### Response monitors

Each real response contains 32 data messages of 256 bytes, for an 8192-byte
body, with 200 unrelated mailbox entries. The peer waits for acknowledgment
of each actual data message before sending the next chunk. The harness checks
chunk boundaries and bodies for per-message `gun:await/3`, shared-monitor
`gun:await/4`, and compiled Gluegun collection.

The synthetic comparison uses 4000 queued data messages of 256 bytes. It
isolates mailbox work but does not represent a network response. Both
comparisons use three repetitions. Monitor-call records use counts from the
executed source paths, not VM call tracing.

Elapsed times include scheduling and peer pacing. Reduction counts cover the
calling process, not total CPU use by Gun, the peer, or tracing helpers.
Gluegun also performs typed decoding and response assembly. These samples do
not prove a production speedup or justify a performance threshold.

### System CA certificates

The harness measures production TLS-default application with a cold Gluegun
cache and two warm-cache connections. It reports decoded CA flat size and
external size outside that timing interval. To establish local TLS, it appends
the generated test CA to the production system trust list.

Process snapshots cover the owner, Gun, and observed SSL workers during setup,
handshake, establishment, and cleanup. Heap words and process memory are
different measures. Binary references can point to shared off-heap data; adding
their sizes across processes would count shared storage more than once.
Snapshots include transient allocations and GC effects. SSL workers that the
harness cannot attribute to the client or server retain an `unknown` label.

The controlled handshake uses extra local trust and process-observation
instrumentation. These are not measurements of an unmodified public HTTPS
request. Decoded CA size is not actual per-connection memory or a saving.
The production CA cache already exists; this deliverable does not change it.

### Header names

[#81](https://github.com/tylerbutler/gluegun/issues/81) and
[#104](https://github.com/tylerbutler/gluegun/pull/104) resolved this candidate.
The current receive path validates `inbound_text(Name)` before Unicode
lowercase. Existing regressions cover malformed names, values, incomplete
UTF-8, header pairs, valid text, and actual wire response headers/trailers.
The harness runs those regressions and reports the candidate as resolved.
It adds no duplicate fix or header timing claim.

## Raw sample results

Local run on 2026-11-14, macOS, OTP 27.2.1 / ERTS 15.2.1, 64-bit words
(8 bytes), two online schedulers, JIT. Baseline: `aac9136`, Gun 2.8.0,
Cowlib 2.22.0, Gluegun 1.0.0-rc.1, Gleam 1.19.2. The independent PR also
includes the later `5f22eaa` main baseline, which changes source documentation,
not these candidate implementations or dependencies.

The following are individual raw samples, not averages or inferred gains.
The machine was not a dedicated benchmark host. Record order, pacing,
instrumentation, and preceding workloads can affect results.

### Cancellation and collection

Each timing cell contains `elapsed_us / caller_reductions`.

| Workload | Repeat 1 | Repeat 2 | Repeat 3 |
| --- | ---: | ---: | ---: |
| Real per-message monitor | 2209 / 7311 | 1767 / 7303 | 4411 / 7303 |
| Real shared monitor | 2157 / 7174 | 2372 / 7174 | 3112 / 7174 |
| Real compiled Gluegun | 1935 / 8773 | 1764 / 8781 | 1880 / 8766 |
| Synthetic per-message monitor | 4151 / 872472 | 4238 / 872399 | 4158 / 872399 |
| Synthetic shared monitor | 3392 / 832836 | 3318 / 830261 | 3182 / 830261 |

The real per-message and Gluegun paths each use 33 monitor/demonitor calls
(headers plus 32 data messages); the shared path uses one pair. The synthetic
paths use 4000 and one monitor calls. Equal body/count checks passed. The
chunk selfcheck rejected both 128-byte and 384-byte fragments despite an
equal combined body and count.

| Cancellation operation | Elapsed us | Caller reductions | Observed result |
| --- | ---: | ---: | --- |
| Immediate drain | 3 | 43 | One real delayed body arrived afterward |
| Suspended Gun barrier | 101012 | 30 | Guard returned timeout |
| Resumed Gun barrier | 13 | 27 | Processing completed; queued body drained |
| Existing delayed-response fixture | 102781 | 1819 | Passed |
| Existing delayed-body fixture | 101159 | 1930 | Passed |

Barrier-worker reductions do not appear in caller reductions.

### CA and TLS

Each connection reported 188 system certificates, 110977 flat words
(887816 bytes), and 592862 external bytes. Warm-cache equality checks passed.
These sizes describe the decoded list, not process allocations.

| Connection | Cache | Defaults-only us / reductions | TLS await-up us / reductions |
| --- | --- | ---: | ---: |
| 1 | Cold | 35133 / 514044 | 31367 / 19 |
| 2 | Warm | 8 / 100 | 2149 / 19 |
| 3 | Warm | 7 / 100 | 2103 / 28 |

The defaults timer excludes CA sizing and printing. `await-up` covers the
remaining asynchronous setup, so it is not total TLS CPU cost.

These raw stage samples list `heap_words / total_heap_words / memory_bytes`
and `binary_reference_count / binary_referenced_bytes`. Refcount histograms
in the live output indicate sharing but do not identify which processes share
a binary. Do not sum referenced bytes as unique allocations.

| Connection | Process/stage | Heap / total / memory | Binary references / bytes |
| --- | --- | ---: | ---: |
| 1 | Owner before defaults | 376 / 470 / 4808 | 5 / 4352 |
| 1 | Owner after defaults | 28690 / 225340 / 1803792 | 490 / 300498 |
| 1 | Owner before handshake | 28690 / 225340 / 1803984 | 447 / 457041 |
| 1 | Gun before handshake | 2586 / 4184 / 34656 | 6 / 170578 |
| 1 | SSL before handshake, unknown | 1598 / 4184 / 34792 | 3 / 1995 |
| 1 | Owner established | 28690 / 226322 / 1811840 | 447 / 457041 |
| 1 | Gun established | 2586 / 4184 / 34600 | 6 / 170578 |
| 1 | Client SSL established | 75113 / 75113 / 602008 | 11 / 8842 |
| 1 | Owner cleaned | 28690 / 227446 / 1820640 | 449 / 457311 |
| 2 | Owner before defaults | 28690 / 225340 / 1803792 | 441 / 290390 |
| 2 | Owner after defaults | 28690 / 225340 / 1803792 | 441 / 290390 |
| 2 | Owner before handshake | 28690 / 225340 / 1803984 | 441 / 290390 |
| 2 | Gun before handshake | 2586 / 6771 / 55328 | 2 / 1890 |
| 2 | Client SSL before handshake | 46422 / 75112 / 601976 | 22 / 7110 |
| 2 | Owner established | 28690 / 226545 / 1813624 | 441 / 290390 |
| 2 | Gun established | 2586 / 6771 / 55200 | 2 / 1890 |
| 2 | Client SSL established | 75113 / 75113 / 601912 | 11 / 8842 |
| 2 | Owner cleaned | 28690 / 227789 / 1823384 | 443 / 290660 |
| 3 | Owner before defaults | 28690 / 225340 / 1803792 | 441 / 290390 |
| 3 | Owner after defaults | 28690 / 225340 / 1803792 | 441 / 290390 |
| 3 | Owner before handshake | 28690 / 225340 / 1803984 | 441 / 290390 |
| 3 | Gun before handshake | 2586 / 6771 / 55328 | 2 / 1890 |
| 3 | Client SSL before handshake | 46422 / 75112 / 601976 | 22 / 7110 |
| 3 | Owner established | 28690 / 226542 / 1813600 | 441 / 290390 |
| 3 | Gun established | 2586 / 6771 / 55200 | 2 / 1890 |
| 3 | Client SSL established | 75113 / 75113 / 601912 | 11 / 8842 |
| 3 | Owner cleaned | 28690 / 227642 / 1822208 | 443 / 290660 |

Connection 1's listed unknown worker has the same PID as the later identified
client SSL worker. The table retains the original unknown stage label. The
live output also records local-peer and other unknown SSL workers. Their
memory does not represent client connection memory.

Owner cleanup snapshots retain the suite-guard monitor; the final assertion
checks its removal. Gun and SSL workers exited. The final result reported
749298 microseconds, zero owned network ports, and zero owned monitors.
The process snapshots do not isolate CA-only memory or establish a copy count.

### Regression evidence and limits

The harness passed four existing cancellation/push regressions and eight
header regressions. The focused client/runtime suite passed 38 tests.
Strict build, format/check, and documentation-example checks passed.

No production optimization, release, dependency change, or user-facing
changelog is part of this deliverable. The suite-expiry path has not had a
deliberate fault-injection run. These local samples do not establish behavior
under sustained load or on other operating systems.
