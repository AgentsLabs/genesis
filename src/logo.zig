pub const LogoLines = struct {
    lines: []const []const u8,
    width: usize,
    height: usize,
};

pub fn getLogo() LogoLines {
    const lines = [_][]const u8{
        "╭──────────────────────────────────────╮",
        "│                                      │",
        "│   ██████╗ ███████╗███╗   ██╗███████╗│",
        "│  ██╔════╝ ██╔════╝████╗  ██║██╔════╝│",
        "│  ██║  ███╗█████╗  ██╔██╗ ██║███████╗│",
        "│  ██║   ██║██╔══╝  ██║╚██╗██║╚════██║│",
        "│  ╚██████╔╝███████╗██║ ╚████║███████║│",
        "│   ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝│",
        "│                                      │",
        "│   A Modern Coding Harness    v0.1.0  │",
        "╰──────────────────────────────────────╯",
    };
    return LogoLines{
        .lines = &lines,
        .width = 42,
        .height = lines.len,
    };
}
