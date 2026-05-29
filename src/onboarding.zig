const std = @import("std");
const tui = @import("tui.zig");

const Step = enum {
    welcome,
    try_help,
    try_read,
    try_bash,
    try_ls,
    try_theme,
    done,
};

pub const Onboarding = struct {
    active: bool,
    step: Step,
    messages: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Onboarding {
        return Onboarding{
            .active = false,
            .step = .welcome,
            .messages = &[_][]const u8{},
            .allocator = allocator,
        };
    }

    pub fn start(self: *Onboarding, screen: *tui.Screen) !void {
        self.active = true;
        self.step = .welcome;
        try self.showStep(screen);
    }

    fn showStep(self: *Onboarding, screen: *tui.Screen) !void {
        screen.status_text = "Onboarding";
        switch (self.step) {
            .welcome => {
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Welcome to Genesis! Let's learn the basics.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Genesis has 4 core tools: read, write, edit, bash.");
                try self.addMsg(screen, " You'll try each one in this tour.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " First, type /help and press Enter to see all commands.");
                try self.addHint(screen, "/help");
            },
            .try_help => {
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Great! /help shows all available commands.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Now let's read a file. Type:");
                try self.addHint(screen, "/read src/logo.zig");
            },
            .try_read => {
                try self.addMsg(screen, "");
                try self.addMsg(screen, " You can read any file with line numbers.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Now let's run a shell command. Type:");
                try self.addHint(screen, "/bash echo \"hello genesis\"");
            },
            .try_bash => {
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Bash lets you run any program from Genesis.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Now let's list files. Type:");
                try self.addHint(screen, "/ls src");
            },
            .try_ls => {
                try self.addMsg(screen, "");
                try self.addMsg(screen, " You can navigate your project with /ls.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Genesis supports custom themes. Type:");
                try self.addHint(screen, "/theme themes/dracula.json");
            },
            .try_theme => {
                try self.addMsg(screen, "");
                try self.addMsg(screen, " Themes change the look and feel.");
                try self.addMsg(screen, " Create your own theme JSON files too.");
                try self.addMsg(screen, "");
                try self.addMsg(screen, " You've completed the onboarding!");
                try self.addMsg(screen, " Type /help anytime to see all commands.");
                try self.addMsg(screen, " Type /exit to quit Genesis.");
            },
            .done => {},
        }
    }

    fn addMsg(_: *Onboarding, screen: *tui.Screen, msg: []const u8) !void {
        try screen.addOutput(msg);
    }

    fn addHint(self: *Onboarding, screen: *tui.Screen, cmd: []const u8) !void {
        const buf = try std.fmt.allocPrint(self.allocator, "   ➜  {s}", .{cmd});
        defer self.allocator.free(buf);
        try screen.addOutput(buf);
    }

    pub fn processInput(self: *Onboarding, screen: *tui.Screen, input: []const u8) !bool {
        if (!self.active) return false;

        const expected = self.expectedCommand();
        if (expected) |exp| {
            if (std.mem.eql(u8, input, exp)) {
                // Correct command - advance
                self.step = switch (self.step) {
                    .welcome => .try_help,
                    .try_help => .try_read,
                    .try_read => .try_bash,
                    .try_bash => .try_ls,
                    .try_ls => .try_theme,
                    .try_theme => .done,
                    .done => .done,
                };
                if (self.step == .done) {
                    self.active = false;
                    screen.status_text = "Ready";
                    try self.addMsg(screen, "");
                    try self.addMsg(screen, " Onboarding complete! You're ready to use Genesis.");
                    try self.addMsg(screen, "");
                } else {
                    try self.showStep(screen);
                }
                return true;
            }
            // Wrong command - show hint
            try screen.addOutput("");
            try self.addMsg(screen, " That's not the right command for this step.");
            try self.addHint(screen, exp);
            return true;
        }
        return false;
    }

    fn expectedCommand(self: *Onboarding) ?[]const u8 {
        return switch (self.step) {
            .welcome => "/help",
            .try_help => "/read src/logo.zig",
            .try_read => "/bash echo \"hello genesis\"",
            .try_bash => "/ls src",
            .try_ls => "/theme themes/dracula.json",
            .try_theme => null,
            .done => null,
        };
    }
};
