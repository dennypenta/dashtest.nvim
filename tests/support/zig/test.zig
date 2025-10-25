const std = @import("std");

test "passing test" {
    const result = 2 + 2;
    try std.testing.expectEqual(4, result);
}

test "another passing test" {
    const value = true;
    try std.testing.expect(value);
}

test "failed test" {
    // This test will fail
    try std.testing.expectEqual(5, 2 + 2);
}

test "another failing test" {
    try std.testing.expect(false);
}

test "test with string comparison" {
    const greeting = "Hello, Zig!";
    try std.testing.expectEqualStrings("Hello, Zig!", greeting);
}
