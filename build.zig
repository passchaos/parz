const std = @import("std");

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

    const tree_sum_mod = b.createModule(.{
        .root_source_file = b.path("bench/tree_sum.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const tree_sum = b.addExecutable(.{
        .name = "parz-tree-sum",
        .root_module = tree_sum_mod,
    });
    const run_tree_sum = b.addRunArtifact(tree_sum);
    if (b.args) |args| run_tree_sum.addArgs(args);
    const bench_tree_sum_step = b.step("bench-tree-sum", "Run the Spice-style tree-sum benchmark");
    bench_tree_sum_step.dependOn(&run_tree_sum.step);

    const for_bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/parallel_for.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const for_bench = b.addExecutable(.{
        .name = "parz-parallel-for",
        .root_module = for_bench_mod,
    });
    const run_for_bench = b.addRunArtifact(for_bench);
    if (b.args) |args| run_for_bench.addArgs(args);
    const bench_for_step = b.step("bench-parallel-for", "Run the flat parallel-for benchmark");
    bench_for_step.dependOn(&run_for_bench.step);

    const for_2d_mod = b.createModule(.{
        .root_source_file = b.path("bench/parallel_for_2d.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const for_2d_bench = b.addExecutable(.{
        .name = "parz-parallel-for-2d",
        .root_module = for_2d_mod,
    });
    const run_for_2d_bench = b.addRunArtifact(for_2d_bench);
    if (b.args) |args| run_for_2d_bench.addArgs(args);
    const bench_for_2d_step = b.step("bench-2d", "Run the 2D parallel-for benchmark");
    bench_for_2d_step.dependOn(&run_for_2d_bench.step);

    const compute_mod = b.createModule(.{
        .root_source_file = b.path("bench/compute.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const compute = b.addExecutable(.{
        .name = "parz-compute",
        .root_module = compute_mod,
    });
    const run_compute = b.addRunArtifact(compute);
    if (b.args) |args| run_compute.addArgs(args);
    const bench_compute_step = b.step("bench-compute", "Run the CPU-bound parallel fold benchmark");
    bench_compute_step.dependOn(&run_compute.step);

    const micro_mod = b.createModule(.{
        .root_source_file = b.path("bench/micro.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const micro = b.addExecutable(.{ .name = "parz-micro", .root_module = micro_mod });
    const run_micro = b.addRunArtifact(micro);
    if (b.args) |args| run_micro.addArgs(args);
    const bench_micro_step = b.step("bench-micro", "Run the fork/join micro benchmark");
    bench_micro_step.dependOn(&run_micro.step);

    const irregular_mod = b.createModule(.{
        .root_source_file = b.path("bench/irregular.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const irregular = b.addExecutable(.{ .name = "parz-irregular", .root_module = irregular_mod });
    const run_irregular = b.addRunArtifact(irregular);
    if (b.args) |args| run_irregular.addArgs(args);
    const bench_irregular_step = b.step("bench-irregular", "Run the skewed fork/join benchmark");
    bench_irregular_step.dependOn(&run_irregular.step);

    const sync_mod = b.createModule(.{
        .root_source_file = b.path("bench/sync.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "parz", .module = parz_mod }},
    });
    const sync_bench = b.addExecutable(.{ .name = "parz-sync-bench", .root_module = sync_mod });
    const run_sync_bench = b.addRunArtifact(sync_bench);
    const bench_sync_step = b.step("bench-sync", "Run sync primitive throughput benchmarks");
    bench_sync_step.dependOn(&run_sync_bench.step);

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
