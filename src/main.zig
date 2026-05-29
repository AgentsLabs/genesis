const std = @import("std");
const tui = @import("tui.zig");
const tools = @import("tools.zig");
const theme = @import("theme.zig");
const logo = @import("logo.zig");

var running: bool = true;
var multiline_mode: bool = false;
var multiline_path: []const u8 = "";
var multiline_line_count: usize = 0;
var multiline_accum: std.ArrayList(u8) = undefined;
var has_theme: bool = false;

fn addOutput(screen: *tui.Screen, prefix: []const u8, text: []const u8) !void {
    const allocator = screen.allocator;
    if (prefix.len > 0) {
        const line = try std.fmt.allocPrint(allocator, "{s} {s}", .{ prefix, text });
        defer allocator.free(line);
        try screen.addOutput(line);
    } else {
        try screen.addOutput(text);
    }
}

fn handleCommand(screen: *tui.Screen, allocator: std.mem.Allocator, theme_mgr: *theme.ThemeManager) !void {
    const input = screen.prompt_buf.items;
    screen.prompt_buf.clearRetainingCapacity();

    if (input.len == 0) return;

    // Echo the command
    const echo_line = try std.fmt.allocPrint(allocator, "genesis> {s}", .{input});
    try screen.addOutput(echo_line);
    defer allocator.free(echo_line);

    // Check if it starts with /
    if (input.len < 1 or input[0] != '/') {
        try addOutput(screen, " ", "Unknown command. Type /help for commands.");
        return;
    }

    // Parse command and args
    const cmd_end = std.mem.indexOfScalar(u8, input[1..], ' ') orelse input.len - 1;
    const cmd = input[1 .. 1 + cmd_end];
    const args_start = 1 + cmd_end + 1;
    const args = if (args_start < input.len) input[args_start..] else "";

    if (std.mem.eql(u8, cmd, "exit") or std.mem.eql(u8, cmd, "quit")) {
        running = false;
        try addOutput(screen, " ", "Goodbye!");
        return;
    }

    if (std.mem.eql(u8, cmd, "clear")) {
        try screen.clearScreen();
        try screen.render(theme_mgr);
        return;
    }

    if (std.mem.eql(u8, cmd, "help")) {
        try addOutput(screen, " ", "");
        try addOutput(screen, " ", "Genesis - A Modern Coding Harness");
        try addOutput(screen, " ", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        try addOutput(screen, " ", "");
        try addOutput(screen, " ", "  /read  <path>     Read file contents with line numbers");
        try addOutput(screen, " ", "  /write <path>     Write multi-line content to a file");
        try addOutput(screen, " ", "  /edit  <path> <old> <new>   Find and replace in file");
        try addOutput(screen, " ", "  /bash  <command>  Execute a shell command");
        try addOutput(screen, " ", "  /ls    [path]     List directory contents");
        try addOutput(screen, " ", "  /theme <path>     Load a theme JSON file");
        try addOutput(screen, " ", "  /clear            Clear the screen");
        try addOutput(screen, " ", "  /help             Show this help message");
        try addOutput(screen, " ", "  /exit             Exit Genesis");
        try addOutput(screen, " ", "");
        try addOutput(screen, " ", "  Ctrl+C / Ctrl+D   Exit Genesis anytime");
        try addOutput(screen, " ", "  Ctrl+L            Clear screen");
        try addOutput(screen, " ", "  Ctrl+U            Clear input line");
        try addOutput(screen, " ", "");
        try addOutput(screen, " ", "  /write example: /write hello.txt, then type content");
        try addOutput(screen, " ", "  and end with '.' on a line by itself.");
        try addOutput(screen, " ", "");
        return;
    }

    if (std.mem.eql(u8, cmd, "ls")) {
        const dir_path = if (args.len > 0) args else ".";
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            try addOutput(screen, " ", try std.fmt.allocPrint(allocator, "Error: cannot open directory - {s}", .{@errorName(err)}));
            return;
        };
        defer dir.close();

        var walker = dir.iterate();
        var list = std.ArrayList(u8).init(allocator);
        while (try walker.next()) |entry| {
            const prefix = if (entry.kind == .directory) "📁 " else "📄 ";
            try list.appendSlice(prefix);
            try list.appendSlice(entry.name);
            try list.append('\n');
        }
        if (list.items.len > 0) {
            _ = list.pop();
        }
        try addOutput(screen, " ", list.items);
        return;
    }

    if (std.mem.eql(u8, cmd, "read")) {
        if (args.len == 0) {
            try addOutput(screen, " ", "Usage: /read <path>");
            return;
        }
        const result = tools.readFile(allocator, args);
        if (result.success) {
            try addOutput(screen, " ", result.output);
        } else {
            try addOutput(screen, " ", result.output);
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "write")) {
        if (args.len == 0) {
            try addOutput(screen, " ", "Usage: /write <path>");
            return;
        }
        multiline_mode = true;
        multiline_path = try allocator.dupe(u8, args);
        multiline_line_count = 0;
        multiline_accum = std.ArrayList(u8).init(allocator);
        try addOutput(screen, " ", "Enter content (end with '.' on a line by itself):");
        screen.status_text = "Writing...";
        return;
    }

    if (std.mem.eql(u8, cmd, "edit")) {
        // Parse args: path, old, new
        if (args.len == 0) {
            try addOutput(screen, " ", "Usage: /edit <path> <old> <new>");
            return;
        }
        // Find first space to separate path from rest
        const first_space = std.mem.indexOfScalar(u8, args, ' ') orelse {
            try addOutput(screen, " ", "Usage: /edit <path> <old> <new>");
            return;
        };
        const path = args[0..first_space];
        const rest = args[first_space + 1 ..];
        if (rest.len == 0) {
            try addOutput(screen, " ", "Usage: /edit <path> <old> <new>");
            return;
        }
        // Find the separator between old and new (using last space)
        const sep_pos = std.mem.lastIndexOfScalar(u8, rest, ' ') orelse {
            try addOutput(screen, " ", "Usage: /edit <path> <old> <new>");
            return;
        };
        const old = rest[0..sep_pos];
        const new = rest[sep_pos + 1 ..];

        const result = tools.editFile(allocator, path, old, new);
        if (result.success) {
            try addOutput(screen, " ", result.output);
        } else {
            try addOutput(screen, " ", result.output);
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "bash")) {
        if (args.len == 0) {
            try addOutput(screen, " ", "Usage: /bash <command>");
            return;
        }
        screen.status_text = "Running...";
        try screen.render(theme_mgr);
        const result = tools.execBash(allocator, args);
        screen.status_text = "Ready";
        if (result.success) {
            try addOutput(screen, " ", result.output);
        } else {
            try addOutput(screen, " ", result.output);
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "theme")) {
        if (args.len == 0) {
            try addOutput(screen, " ", try std.fmt.allocPrint(allocator, "Current theme: {s}", .{theme_mgr.current.name}));
            return;
        }
        theme_mgr.loadFromFile(args) catch |err| {
            try addOutput(screen, " ", try std.fmt.allocPrint(allocator, "Error: cannot load theme '{s}' - {s}", .{ args, @errorName(err) }));
            return;
        };
        try addOutput(screen, " ", try std.fmt.allocPrint(allocator, "Theme loaded: {s}", .{theme_mgr.current.name}));
        return;
    }

    try addOutput(screen, " ", try std.fmt.allocPrint(allocator, "Unknown command: /{s}. Type /help.", .{cmd}));
}

fn handleKey(screen: *tui.Screen, allocator: std.mem.Allocator, theme_mgr: *theme.ThemeManager) !void {
    const key = screen.readKey() catch |err| {
        try addOutput(screen, " ", try std.fmt.allocPrint(allocator, "Input error: {s}", .{@errorName(err)}));
        return;
    };
    const b = key orelse return;

    if (multiline_mode) {
        switch (b) {
            0x03, 0x04 => {
                // Cancel multiline mode
                multiline_mode = false;
                multiline_accum.deinit();
                allocator.free(multiline_path);
                screen.status_text = "Ready";
                try addOutput(screen, " ", "Cancelled.");
            },
            0x0A, 0x0D => {
                // Enter - commit line
                const line = screen.prompt_buf.items;
                if (line.len == 1 and line[0] == '.') {
                    // End multiline mode
                    const content = multiline_accum.items;
                    const path = multiline_path;
                    multiline_mode = false;
                    screen.status_text = "Ready";
                    const result = tools.writeFile(allocator, path, content);
                    if (result.success) {
                        try addOutput(screen, " ", result.output);
                    } else {
                        try addOutput(screen, " ", result.output);
                    }
                    allocator.free(path);
                    multiline_accum.deinit();
                } else {
                    // Add line to accumulator
                    multiline_accum.appendSlice(line) catch {};
                    multiline_accum.append('\n') catch {};
                    multiline_line_count += 1;
                    const count_line = try std.fmt.allocPrint(allocator, "  line {d}: {s}", .{ multiline_line_count, line });
                    try screen.addOutput(count_line);
                }
                screen.prompt_buf.clearRetainingCapacity();
            },
            0x7F, 0x08 => {
                // Backspace
                _ = screen.prompt_buf.popOrNull();
            },
            0x15 => {
                // Ctrl+U - clear line
                screen.prompt_buf.clearRetainingCapacity();
            },
            else => {
                if (b >= 0x20 and b <= 0x7E) {
                    try screen.prompt_buf.append(b);
                }
            },
        }
    } else {
        switch (b) {
            0x03, 0x04 => {
                // Ctrl+C, Ctrl+D - exit
                try addOutput(screen, " ", "Exiting Genesis...");
                running = false;
            },
            0x0A, 0x0D => {
                // Enter
                try handleCommand(screen, allocator, theme_mgr);
            },
            0x09 => {
                // Tab - try to autocomplete /commands
                const buf = screen.prompt_buf.items;
                if (buf.len == 0 or buf[0] != '/') {
                    try screen.prompt_buf.append('\t');
                } else {
                    // Simple completion for commands
                    const partial = buf[1..];
                    const commands = [_][]const u8{ "read", "write", "edit", "bash", "ls", "clear", "help", "exit", "theme" };
                    inline for (commands) |cmd_name| {
                        if (std.mem.startsWith(u8, cmd_name, partial)) {
                            screen.prompt_buf.clearRetainingCapacity();
                            try screen.prompt_buf.append('/');
                            try screen.prompt_buf.appendSlice(cmd_name);
                            try screen.prompt_buf.append(' ');
                            break;
                        }
                    }
                }
            },
            0x0C => {
                // Ctrl+L - clear screen
                try screen.clearScreen();
            },
            0x15 => {
                // Ctrl+U - clear input line
                screen.prompt_buf.clearRetainingCapacity();
            },
            0x7F, 0x08 => {
                // Backspace
                _ = screen.prompt_buf.popOrNull();
            },
            else => {
                if (b >= 0x20 and b <= 0x7E) {
                    try screen.prompt_buf.append(b);
                }
            },
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check if running in terminal
    if (!std.posix.isatty(std.io.getStdIn().handle)) {
        std.debug.print("Genesis requires a terminal.\n", .{});
        std.process.exit(1);
    }

    // Initialize screen
    var screen = tui.Screen.init(allocator);
    defer screen.deinit();

    // Enable raw mode
    screen.enableRawMode() catch |err| {
        std.debug.print("Warning: could not set raw mode: {s}\n", .{@errorName(err)});
    };

    // Initialize theme
    var theme_mgr = theme.ThemeManager.init(allocator);
    // Try loading default theme from themes directory
    if (std.fs.cwd().openFile("themes/default.json", .{})) |file| {
        file.close();
        theme_mgr.loadFromFile("themes/default.json") catch {};
        has_theme = true;
    } else |_| {}

    // Welcome message
    try screen.addOutput("Welcome to Genesis v0.1.0");
    try screen.addOutput("A Modern Coding Harness");
    try screen.addOutput("");
    try screen.addOutput("Type /help for available commands.");

    // Main loop
    while (running) {
        try screen.render(&theme_mgr);
        try handleKey(&screen, allocator, &theme_mgr);
    }

    // Clean shutdown
    theme_mgr.deinit();
    try screen.disableRawMode();
}
