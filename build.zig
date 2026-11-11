const std = @import("std");

const ToolOptions = struct {
    name: []const u8,
    source: []const u8,
    step: []const u8,
    description: []const u8,
    optimize: std.builtin.OptimizeMode,
    /// Forward `--` arguments to the run step. Harmless for tools that ignore
    /// them and keeps the command line uniform across benchmarks.
    forward_args: bool = true,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parz_mod = b.addModule("parz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{ .root_module = parz_mod });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const integration_mod = b.createModule(.{
        .root_source_file = b.path("test/integration.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const integration_tests = b.addTest(.{ .root_module = integration_mod });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_step = b.step("test", "Run parz tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // Checks and benchmarks share the same shape: a parz-importing executable
    // plus a named run step. Keep the wiring here so each entry stays a
    // one-line declaration.
    const addTool = struct {
        fn add(
            b_: *std.Build,
            parz: *std.Build.Module,
            resolved_target: std.Build.ResolvedTarget,
            options: ToolOptions,
        ) *std.Build.Step {
            const module = b_.createModule(.{
                .root_source_file = b_.path(options.source),
                .target = resolved_target,
                .optimize = options.optimize,
                .imports = &.{.{ .name = "parz", .module = parz }},
            });
            const exe = b_.addExecutable(.{
                .name = options.name,
                .root_module = module,
            });
            const run = b_.addRunArtifact(exe);
            if (options.forward_args) {
                if (b_.args) |args| run.addArgs(args);
            }
            const step = b_.step(options.step, options.description);
            step.dependOn(&run.step);
            return step;
        }
    }.add;

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-numa-check",
        .source = "bench/numa.zig",
        .step = "check-numa",
        .description = "Check NUMA policy, fallback and allocator lifetime",
        .optimize = optimize,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-worker-layout",
        .source = "bench/worker_layout.zig",
        .step = "check-worker-layout",
        .description = "Report worker field layout across context alignments",
        .optimize = optimize,
        .forward_args = false,
    });

    const bench_tree_sum_step = addTool(b, parz_mod, target, .{
        .name = "parz-tree-sum",
        .source = "bench/tree_sum.zig",
        .step = "bench-tree-sum",
        .description = "Run the Spice-style tree-sum benchmark",
        .optimize = .ReleaseFast,
    });

    const bench_for_step = addTool(b, parz_mod, target, .{
        .name = "parz-parallel-for",
        .source = "bench/parallel_for.zig",
        .step = "bench-parallel-for",
        .description = "Run the flat parallel-for benchmark",
        .optimize = .ReleaseFast,
    });

    const bench_for_2d_step = addTool(b, parz_mod, target, .{
        .name = "parz-parallel-for-2d",
        .source = "bench/parallel_for_2d.zig",
        .step = "bench-2d",
        .description = "Run the 2D parallel-for benchmark",
        .optimize = .ReleaseFast,
    });

    const bench_compute_step = addTool(b, parz_mod, target, .{
        .name = "parz-compute",
        .source = "bench/compute.zig",
        .step = "bench-compute",
        .description = "Run the CPU-bound parallel fold benchmark",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-infallible-fold",
        .source = "bench/infallible_fold.zig",
        .step = "bench-infallible-fold",
        .description = "Compare infallible fold paths and dispatch allocations",
        .optimize = .ReleaseFast,
    });
    _ = addTool(b, parz_mod, target, .{
        .name = "parz-flat-dispatch",
        .source = "bench/flat_dispatch.zig",
        .step = "bench-flat-dispatch",
        .description = "Measure flat cost hints, context reuse and dispatch scratch",
        .optimize = .ReleaseFast,
    });
    _ = addTool(b, parz_mod, target, .{
        .name = "parz-pool-idle",
        .source = "bench/pool_idle.zig",
        .step = "bench-pool-idle",
        .description = "Expose a controlled idle or held-caller pool interval",
        .optimize = .ReleaseFast,
    });
    _ = addTool(b, parz_mod, target, .{
        .name = "parz-multi-caller",
        .source = "bench/multi_caller.zig",
        .step = "bench-multi-caller",
        .description = "Measure concurrent caller throughput and latency on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    const bench_micro_step = addTool(b, parz_mod, target, .{
        .name = "parz-micro",
        .source = "bench/micro.zig",
        .step = "bench-micro",
        .description = "Run the fork/join micro benchmark",
        .optimize = .ReleaseFast,
    });

    const bench_irregular_step = addTool(b, parz_mod, target, .{
        .name = "parz-irregular",
        .source = "bench/irregular.zig",
        .step = "bench-irregular",
        .description = "Run the skewed fork/join benchmark",
        .optimize = .ReleaseFast,
    });

    const bench_sync_step = addTool(b, parz_mod, target, .{
        .name = "parz-sync-bench",
        .source = "bench/sync.zig",
        .step = "bench-sync",
        .description = "Run sync primitive throughput benchmarks",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-spsc-bench",
        .source = "bench/spsc.zig",
        .step = "bench-spsc",
        .description = "Compare checksum-verified SPSC paths on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-spsc-batch",
        .source = "bench/spsc_batch.zig",
        .step = "bench-spsc-batch",
        .description = "Compare scalar and batch SPSC transfers on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-mpsc-batch",
        .source = "bench/mpsc_batch.zig",
        .step = "bench-mpsc-batch",
        .description = "Compare scalar and batch MPSC transfers on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-sharded-mpsc-batch",
        .source = "bench/sharded_mpsc_batch.zig",
        .step = "bench-sharded-mpsc-batch",
        .description = "Compare scalar and batch sharded MPSC transfers on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-blocking-batch",
        .source = "bench/blocking_batch.zig",
        .step = "bench-blocking-batch",
        .description = "Compare scalar and batch BlockingQueue transfers on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-treiber-batch",
        .source = "bench/treiber_batch.zig",
        .step = "bench-treiber-batch",
        .description = "Compare scalar and batch TreiberStack transfers on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    _ = addTool(b, parz_mod, target, .{
        .name = "parz-semaphore-batch",
        .source = "bench/semaphore_batch.zig",
        .step = "bench-semaphore-batch",
        .description = "Compare scalar and batch semaphore transfers on fixed CPUs",
        .optimize = .ReleaseFast,
    });

    const bench_step = b.step("bench", "Run all parz benchmarks");
    bench_step.dependOn(bench_tree_sum_step);
    bench_step.dependOn(bench_for_step);
    bench_step.dependOn(bench_for_2d_step);
    bench_step.dependOn(bench_compute_step);
    bench_step.dependOn(bench_micro_step);
    bench_step.dependOn(bench_irregular_step);
    bench_step.dependOn(bench_sync_step);

    const compare_parz_mod = b.createModule(.{
        .root_source_file = b.path("bench/compare/parz_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const compare_parz = b.addExecutable(.{
        .name = "compare-parz",
        .root_module = compare_parz_mod,
    });
    const compare_step = b.step("bench-compare", "Build the parz comparison benchmark");
    compare_step.dependOn(&b.addInstallArtifact(compare_parz, .{}).step);

    if (b.option([]const u8, "spice-dir", "Path to a judofyr/spice clone")) |spice_dir| {
        const spice_root = b.pathJoin(&.{ spice_dir, "src", "root.zig" });
        const spice_mod = b.addModule("spice", .{
            .root_source_file = .{ .cwd_relative = spice_root },
            .target = target,
            .optimize = .ReleaseFast,
        });
        const compare_spice_mod = b.createModule(.{
            .root_source_file = b.path("bench/compare/spice_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "spice", .module = spice_mod }},
        });
        const compare_spice = b.addExecutable(.{
            .name = "compare-spice",
            .root_module = compare_spice_mod,
        });
        compare_step.dependOn(&b.addInstallArtifact(compare_spice, .{}).step);
    }
}
