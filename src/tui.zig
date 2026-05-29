const std = @import("std");
const Theme = @import("theme.zig");
const Logo = @import("logo.zig");

pub const Screen = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    output_lines: std.ArrayList([]const u8),
    prompt_buf: std.ArrayList(u8),
    status_text: []const u8,
    raw_mode: bool,
    original_termios: std.posix.termios,
    show_full_logo: bool,

    pub fn init(allocator: std.mem.Allocator) Screen {
        var s = Screen{
            .allocator = allocator,
            .width = 80,
            .height = 24,
            .output_lines = std.ArrayList([]const u8).init(allocator),
            .prompt_buf = std.ArrayList(u8).init(allocator),
            .status_text = "Ready",
            .raw_mode = false,
            .original_termios = undefined,
            .show_full_logo = true,
        };
        s.refreshSize();
        return s;
    }

    pub fn enableRawMode(self: *Screen) !void {
        const fd = std.io.getStdIn().handle;
        self.original_termios = try std.posix.tcgetattr(fd);
        var raw = self.original_termios;

        raw.iflag.IXON = false;
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        raw.cflag.CSIZE = .CS8;

        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;

        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(fd, std.posix.TCSA.FLUSH, raw);
        self.raw_mode = true;
    }

    pub fn disableRawMode(self: *Screen) !void {
        if (!self.raw_mode) return;
        const fd = std.io.getStdIn().handle;
        try std.posix.tcsetattr(fd, std.posix.TCSA.FLUSH, self.original_termios);
        self.raw_mode = false;
    }

    pub fn refreshSize(self: *Screen) void {
        var ws: std.posix.winsize = std.mem.zeroes(std.posix.winsize);
        const rc = std.os.linux.ioctl(std.io.getStdOut().handle, std.os.linux.T.IOCGWINSZ, @intFromPtr(&ws));
        if (rc == 0) {
            if (ws.ws_col > 0) self.width = ws.ws_col;
            if (ws.ws_row > 0) self.height = ws.ws_row;
        }
    }

    pub fn addOutput(self: *Screen, text: []const u8) !void {
        const owned = try self.allocator.dupe(u8, text);
        try self.output_lines.append(owned);
        if (self.output_lines.items.len > 500) {
            const old = self.output_lines.orderedRemove(0);
            self.allocator.free(old);
        }
    }

    fn setFg(writer: anytype, color: Theme.Color) !void {
        const r: u8 = @truncate((color >> 16) & 0xFF);
        const g: u8 = @truncate((color >> 8) & 0xFF);
        const b: u8 = @truncate(color & 0xFF);
        try writer.print("\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
    }

    fn setBg(writer: anytype, color: Theme.Color) !void {
        const r: u8 = @truncate((color >> 16) & 0xFF);
        const g: u8 = @truncate((color >> 8) & 0xFF);
        const b: u8 = @truncate(color & 0xFF);
        try writer.print("\x1b[48;2;{d};{d};{d}m", .{ r, g, b });
    }

    fn resetStyle(writer: anytype) !void {
        try writer.writeAll("\x1b[0m");
    }

    pub fn clearScreen(self: *Screen) !void {
        self.output_lines.clearAndFree();
        self.prompt_buf.clearRetainingCapacity();
        self.show_full_logo = true;
    }

    pub fn render(self: *Screen, theme: *const Theme.ThemeManager) !void {
        self.refreshSize();
        const out = std.io.getStdOut().writer();
        const colors = &theme.current.colors;

        // Hide cursor and reset
        try out.writeAll("\x1b[?25l\x1b[0m");

        // Calculate layout
        const logo = Logo.getLogo();
        const logo_lines = if (self.show_full_logo) logo.lines.len else 0;
        const head_lines: usize = if (logo_lines > 0) logo_lines else 1;
        const area_overhead: usize = head_lines + 1 + 1 + 1 + 1; // logo/head + sep + prompt + input_sep + status
        const min_output_lines: usize = 3;
        const output_avail = if (self.height > area_overhead + min_output_lines)
            self.height - area_overhead
        else
            min_output_lines;

        // Set background and move to home (no clear to avoid flicker)
        try setBg(out, colors.background);
        try out.writeAll("\x1b[H");

        // Draw logo or minimal header
        if (logo_lines > 0) {
            try setFg(out, colors.primary);
            for (logo.lines) |line| {
                try out.writeAll("\x1b[0K");
                try out.writeAll(line);
                try out.writeAll("\n");
            }
        } else {
            try setFg(out, colors.text_dim);
            try out.writeAll("\x1b[0K");
            try out.writeAll("  genesis v0.1.0");
            try resetStyle(out);
            try out.writeAll("\n");
        }

        // Separator
        try resetStyle(out);
        try setFg(out, colors.text_dim);
        try out.writeAll("\x1b[0K");
        var i: usize = 0;
        while (i < self.width) : (i += 1) {
            try out.writeAll("─");
        }
        try resetStyle(out);
        try out.writeAll("\n");

        // Output area - show latest lines
        const total = self.output_lines.items.len;
        const start_idx = if (total > output_avail) total - output_avail else 0;
        const count = total - start_idx;

        if (count == 0) {
            try setFg(out, colors.text_dim);
            try out.writeAll("\x1b[0K  Welcome to Genesis. Type /onboard for a tutorial.\n");
            try resetStyle(out);
        } else {
            for (self.output_lines.items[start_idx..]) |line| {
                try out.writeAll("\x1b[0K");
                try setFg(out, colors.text);
                try out.writeAll(line);
                try resetStyle(out);
                try out.writeAll("\n");
            }
        }

        // Fill remaining output area
        const fill_start: usize = if (count == 0) @as(usize, 1) else count;
        var fill: usize = fill_start;
        while (fill < output_avail) : (fill += 1) {
            try out.writeAll("\x1b[0K\n");
        }

        // Input prompt
        try setFg(out, colors.prompt);
        try out.writeAll("\x1b[0K┌─");
        try resetStyle(out);
        try setFg(out, colors.text);
        try out.writeAll(" genesis ");
        try resetStyle(out);
        try setFg(out, colors.info);
        try out.writeAll(">");
        try resetStyle(out);
        try out.writeAll(" ");
        try out.writeAll(self.prompt_buf.items);

        // Clear to end of line
        if (self.prompt_buf.items.len < self.width) {
            try out.writeAll("\x1b[0K");
        }
        try out.writeAll("\n");

        // Separator line
        try setFg(out, colors.text_dim);
        try out.writeAll("\x1b[0K├");
        i = 0;
        while (i < self.width - 1) : (i += 1) {
            try out.writeAll("─");
        }
        try resetStyle(out);
        try out.writeAll("\n");

        // Status bar
        try setBg(out, colors.surface);
        try setFg(out, colors.text_dim);
        try out.writeAll("\x1b[0K  ■ ");
        try setFg(out, colors.info);
        try out.print("{s}", .{self.status_text});

        // Right-align theme name
        const theme_label = try std.fmt.allocPrint(self.allocator, "theme: {s}", .{theme.current.name});
        defer self.allocator.free(theme_label);
        const right_pad = if (theme_label.len + 2 < self.width) self.width - theme_label.len - 2 else 0;
        try out.writeByteNTimes(' ', right_pad);
        try setFg(out, colors.text_dim);
        try out.writeAll(" ");
        try out.writeAll(theme_label);
        try out.writeAll(" ");
        try resetStyle(out);
        try setBg(out, colors.background);

        // Position cursor at input line
        const cursor_col: usize = 13 + self.prompt_buf.items.len;
        const clamped_col = if (cursor_col > self.width) self.width else cursor_col;
        try out.print("\x1b[{d};{d}H", .{ self.height, clamped_col });
        try out.writeAll("\x1b[?25h");
    }

    pub fn readKey(self: *Screen) !?u8 {
        _ = self;
        const stdin = std.io.getStdIn();
        var buf: [1]u8 = undefined;
        const n = try stdin.read(&buf);
        if (n == 0) return null;
        return buf[0];
    }

    pub fn deinit(self: *Screen) void {
        const out = std.io.getStdOut().writer();
        out.writeAll("\x1b[2J\x1b[H\x1b[?25h\x1b[0m") catch {};
        self.disableRawMode() catch {};
        for (self.output_lines.items) |line| {
            self.allocator.free(line);
        }
        self.output_lines.deinit();
        self.prompt_buf.deinit();
    }
};
