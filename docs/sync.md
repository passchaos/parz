# Synchronization primitives

`parz.sync` is independent of the scheduler. It depends only on `std`, uses
bounded storage, and allocates only in `init`.

| Type | Model | Blocking |
|---|---|---|
| `SpscQueue(T)` | Single-producer/single-consumer ring | No |
| `MpscQueue(T)` | Multi-producer/single-consumer FIFO | No |
| `ShardedMpscQueue(T, shards)` | Per-producer SPSC shards | No |
| `BlockingQueue(T)` | Multi-producer/multi-consumer ring | Yes (`std.Io`) |
| `TreiberStack(T)` | Multi-producer/single-consumer stack | No |
| `Semaphore` | Counting permits | Yes (`std.Io`) |
| `WaitGroup` | Completion counter | Yes (`std.Io`) |

## SPSC queue

`SpscQueue(T)` caches the opposite endpoint's position until a possible full or
empty boundary. Producer state, consumer state, and immutable buffer metadata
occupy separate cache lines. This reduces communication between cores at the
cost of larger queue metadata: 384 bytes on x86_64 using Zig's 128-byte padding
unit. Sharded MPSC queues inherit this layout. Single-threaded use is
supported; same-thread throughput is measured separately in the SPSC benchmark.

```zig
var queue = try parz.sync.SpscQueue(Message).init(allocator, 1024);
defer queue.deinit();

if (queue.tryPush(message)) { ... }
const next = queue.tryPop() orelse { ... };
```

Slice transfers are partial and allocation-free:

```zig
const pushed = queue.tryPushSlice(pending); // accepted prefix, possibly zero
const popped = queue.tryPopSlice(received); // received[0..popped] is valid
```

Keep one producer and one consumer. Slice transfers may be mixed with
`tryPush`/`tryPop`, preserve FIFO order, and publish/free a whole batch with one
release store. Input/output slices must not alias queue storage. A pop leaves
the unused output suffix untouched.

`len()` snapshots are approximate during concurrent updates and always bounded
by capacity. Exact when quiescent.

## MPSC queue

`MpscQueue(T)` is a bounded multi-producer/single-consumer FIFO. The consumer
position is a plain field, so it does not share a cache line with the producers'
enqueue position.

`tryPushSlice` and `tryPopSlice` provide partial batch transfers:

- For capacities of four or more, a producer reserves an available input prefix
  with one CAS and publishes each slot separately.
- One- and two-slot queues use scalar operations; another producer may
  interleave between those scalar pushes.
- The consumer copies a ready prefix, stopping at the first unpublished slot;
  later producers cannot bypass an earlier reservation.
- Both operations return the transferred count, support mixing with scalar
  operations, allocate nothing, and transfer at most the queue capacity.
- Input/output must not alias queue storage, and an unused output suffix stays
  untouched.
- FIFO follows reservation order; individual producer sequences retain their
  order. A stalled producer can temporarily prevent the consumer from reaching
  later ready slots.

A one-slot ring needs distinct empty/reserved/ready states because the usual
sequence numbers coincide for "published at pos" and "free for pos + 1" when
capacity is one.

## Sharded MPSC queue

`ShardedMpscQueue(T, shards)` gives each producer a private SPSC shard, so
producers never contend. The single consumer round-robins across shards.

- Ordering is FIFO per shard, not globally.
- `tryPush(shard_index, value)` and `tryPushSlice(shard_index, values)` are
  producer-owned operations.
- `tryPop()` visits each shard at most once per call from its round-robin
  cursor.
- `tryPopSlice(output)` fills an output prefix and starts the next call at the
  following shard. Empty slices, partial transfers, scalar/slice mixing, and
  counter wrap are supported without allocation.

## Blocking queue

`BlockingQueue(T)` is a bounded blocking MPMC queue using `std.Io`. Each
operation copies at most two ring segments while holding the mutex once.

```zig
var queue = try parz.sync.BlockingQueue(Message).init(allocator, 1024);
defer queue.deinit();

try queue.put(io, message);       // waits while full
const next = try queue.get(io);   // waits while empty

// Batch forms wait for at least one transferable element, then return the
// explicit partial-progress count.
const written = try queue.putSlice(io, pending);
const read = try queue.getSlice(io, received);
```

`tryPut`/`tryGet` and `tryPutSlice`/`tryGetSlice` are non-blocking. Blocking
forms wait for at least one slot/value and then return the transferred prefix,
so a caller always knows its progress. Unused output suffixes remain untouched.
`putSlice`/`getSlice` are cancelable through `std.Io`.

## Treiber stack

`TreiberStack(T)` is a multi-producer/single-consumer LIFO stack. Nodes are
caller-owned.

```zig
var stack = parz.sync.TreiberStack(Message){};
var node = parz.sync.TreiberStack(Message).Node{ .value = message };
stack.push(&node);
if (stack.pop()) |popped| { ... }
```

With one consumer, ABA cannot occur: producers only push, and the consumer is
the only thread that removes a node, so a head pointer cannot be popped and
re-pushed between the consumer's load and store.

`pushSlice(nodes)` publishes a contiguous caller-owned node slice with one count
update and one successful head CAS; it is equivalent to scalar pushes in slice
order. `popSlice(output)` detaches a stack-order prefix with one successful CAS.
Output entries are node pointers, the unused suffix is untouched, and no memory
is allocated.

`len()` includes pushes that have reserved their count before publishing their
node; it is exact after operations have finished.

## Semaphore

`Semaphore` is a counting semaphore. `wait` may be cancelled by the supplied
`std.Io`; `waitUncancelable` cannot.

```zig
var permits = parz.sync.Semaphore.init(initial_permits);
permits.postMany(io, produced);
try permits.waitMany(io, required);
```

Batch operations:

- `postMany` releases several permits with one lock and one initial wake-up.
  Each waiter signals the next while permits remain, matching
  `std.Io.Semaphore`.
- `waitMany` atomically acquires the complete request, waiting until it is
  available. Zero returns immediately.
- `waitManyUncancelable` is the uncancelable form.

Wide waiters are tracked under the semaphore mutex. The semaphore broadcasts
when necessary so a large request cannot strand permits needed by a smaller
waiter.

## Wait group

```zig
var group = parz.sync.WaitGroup{};
group.add(io, workers);
// each worker:
group.done(io);
group.wait(io);
```

`doneMany` completes several members with one lock. `waitCancelable`
complements the existing uncancelable `wait`.

## Validation

Sync changes require the normal test gates plus ThreadSanitizer:

```sh
zig build test
zig build test -Doptimize=ReleaseSafe
zig test src/root.zig -fsanitize-thread -OReleaseSafe
```

Batch-transfer evidence is recorded in:

- [SPSC batch](validation/2026-11-07-spsc-batch/README.md)
- [MPSC batch](validation/2026-11-07-mpsc-batch/README.md)
- [Sharded MPSC batch](validation/2026-11-07-sharded-mpsc-batch/README.md)
- [BlockingQueue batch](validation/2026-11-07-blocking-batch/README.md)
- [Treiber batch](validation/2026-11-07-treiber-batch/README.md)
- [Coordination batch](validation/2026-11-07-coordination-batch/README.md)
- [Cached SPSC layout](validation/2026-11-07-cached-spsc/README.md)
