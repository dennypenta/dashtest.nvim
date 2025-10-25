const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the test step
    const test_step = b.step("test", "Run unit tests");

    const test_filter = b.option([]const []const u8, "test-filter", "Test filter");
    // Add tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            // unit test is server module, not main,
            // because main uses "build" info which is unavailable in unit tests for
            // std.testing.refAllDecls(@This())
            .root_source_file = b.path("test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = if (test_filter) |filter| filter else &[_][]const u8{},
    });

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
