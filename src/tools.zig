const std = @import("std");

pub const ToolResult = struct {
    success: bool,
    output: []const u8,
};

fn allocPrint(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, fmt, args) catch unreachable;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ToolResult {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot open '{s}' - {s}", .{ path, @errorName(err) }) };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot read '{s}' - {s}", .{ path, @errorName(err) }) };
    };
    defer allocator.free(content);

    if (content.len == 0) {
        return ToolResult{ .success = true, .output = allocPrint(allocator, "(empty file)", .{}) };
    }

    var buf = std.ArrayList(u8).init(allocator);
    var line_num: usize = 1;
    var pos: usize = 0;

    while (pos < content.len) {
        const end = std.mem.indexOfScalarPos(u8, content, pos, '\n') orelse content.len;
        const line = content[pos..end];
        const prefix = allocPrint(allocator, "{d:>4} │ ", .{line_num});
        buf.appendSlice(prefix) catch {};
        allocator.free(prefix);
        buf.appendSlice(line) catch {};
        buf.append('\n') catch {};
        line_num += 1;
        pos = end + 1;
    }

    return ToolResult{ .success = true, .output = buf.toOwnedSlice() catch unreachable };
}

pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) ToolResult {
    const file = std.fs.cwd().createFile(path, .{}) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot create '{s}' - {s}", .{ path, @errorName(err) }) };
    };
    defer file.close();

    file.writeAll(content) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot write '{s}' - {s}", .{ path, @errorName(err) }) };
    };

    return ToolResult{ .success = true, .output = allocPrint(allocator, "Wrote {d} bytes to {s}", .{ content.len, path }) };
}

pub fn editFile(allocator: std.mem.Allocator, path: []const u8, old: []const u8, new: []const u8) ToolResult {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot open '{s}' - {s}", .{ path, @errorName(err) }) };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot read '{s}' - {s}", .{ path, @errorName(err) }) };
    };
    defer allocator.free(content);

    if (std.mem.indexOf(u8, content, old) == null) {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: pattern not found in '{s}'", .{path}) };
    }

    var result = std.ArrayList(u8).init(allocator);
    var start: usize = 0;
    var replace_count: usize = 0;

    while (std.mem.indexOfPos(u8, content, start, old)) |pos| {
        result.appendSlice(content[start..pos]) catch {};
        result.appendSlice(new) catch {};
        start = pos + old.len;
        replace_count += 1;
    }
    result.appendSlice(content[start..]) catch {};

    const out_file = std.fs.cwd().createFile(path, .{}) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot write '{s}' - {s}", .{ path, @errorName(err) }) };
    };
    defer out_file.close();
    out_file.writeAll(result.items) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot write '{s}' - {s}", .{ path, @errorName(err) }) };
    };

    return ToolResult{ .success = true, .output = allocPrint(allocator, "Replaced {d} occurrence(s) in {s}", .{ replace_count, path }) };
}

pub fn execBash(allocator: std.mem.Allocator, command: []const u8) ToolResult {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "/bin/sh", "-c", command },
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch |err| {
        return ToolResult{ .success = false, .output = allocPrint(allocator, "Error: cannot execute command - {s}", .{@errorName(err) }) };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    var output = std.ArrayList(u8).init(allocator);
    if (result.stdout.len > 0) {
        output.appendSlice(result.stdout) catch {};
    }
    if (result.stderr.len > 0) {
        if (result.stdout.len > 0 and result.stdout[result.stdout.len - 1] != '\n') {
            output.append('\n') catch {};
        }
        output.appendSlice(result.stderr) catch {};
    }

    const exit_code = switch (result.term) {
        .Exited => |code| code,
        .Signal => |sig| 128 + sig,
        else => 1,
    };
    const success = exit_code == 0;

    if (output.items.len > 0 and output.items[output.items.len - 1] == '\n') {
        _ = output.pop();
    }

    const output_str = if (output.items.len > 0)
        (output.toOwnedSlice() catch unreachable)
    else if (success)
        allocPrint(allocator, "(completed, exit {d})", .{exit_code})
    else
        allocPrint(allocator, "(failed, exit {d})", .{exit_code});

    return ToolResult{ .success = success, .output = output_str };
}
