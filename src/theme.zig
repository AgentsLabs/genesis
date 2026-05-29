const std = @import("std");

pub const Color = u32;

pub const ThemeColors = struct {
    primary: Color = 0x7aa2f7,
    secondary: Color = 0xbb9af7,
    success: Color = 0x9ece6a,
    err: Color = 0xf7768e,
    warning: Color = 0xe0af68,
    info: Color = 0x7dcfff,
    text: Color = 0xc0caf5,
    text_dim: Color = 0x565f89,
    background: Color = 0x1a1b26,
    surface: Color = 0x24283b,
    surface_alt: Color = 0x1f2335,
    border: Color = 0x3b4261,
    prompt: Color = 0x7aa2f7,
};

pub const Theme = struct {
    name: []const u8,
    author: []const u8 = "Genesis",
    description: []const u8 = "",
    colors: ThemeColors,
};

pub const ThemeManager = struct {
    allocator: std.mem.Allocator,
    current: Theme,

    pub fn init(allocator: std.mem.Allocator) ThemeManager {
        return ThemeManager{
            .allocator = allocator,
            .current = Theme{
                .name = "",
                .author = "",
                .description = "",
                .colors = ThemeColors{},
            },
        };
    }

    pub fn deinit(self: *ThemeManager) void {
        self.freeCurrentStrings();
    }

    fn freeCurrentStrings(self: *ThemeManager) void {
        if (self.current.name.len > 0) self.allocator.free(self.current.name);
        if (self.current.author.len > 0) self.allocator.free(self.current.author);
        if (self.current.description.len > 0) self.allocator.free(self.current.description);
    }

    pub fn loadFromFile(self: *ThemeManager, path: []const u8) !void {
        self.freeCurrentStrings();
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();
        const root = parsed.value;

        const name = root.object.get("name").?.string;
        const author = if (root.object.get("author")) |v| v.string else "Anonymous";
        const description = if (root.object.get("description")) |v| v.string else "";
        const colors = try parseColors(root.object.get("colors").?);

        self.current = Theme{
            .name = try self.allocator.dupe(u8, name),
            .author = try self.allocator.dupe(u8, author),
            .description = try self.allocator.dupe(u8, description),
            .colors = colors,
        };
    }

    fn parseColors(value: std.json.Value) !ThemeColors {
        var colors = ThemeColors{};
        const obj = value.object;
        if (obj.get("primary")) |v| colors.primary = try hexToColor(v.string);
        if (obj.get("secondary")) |v| colors.secondary = try hexToColor(v.string);
        if (obj.get("success")) |v| colors.success = try hexToColor(v.string);
        if (obj.get("error")) |v| colors.err = try hexToColor(v.string);
        if (obj.get("warning")) |v| colors.warning = try hexToColor(v.string);
        if (obj.get("info")) |v| colors.info = try hexToColor(v.string);
        if (obj.get("text")) |v| colors.text = try hexToColor(v.string);
        if (obj.get("text_dim")) |v| colors.text_dim = try hexToColor(v.string);
        if (obj.get("background")) |v| colors.background = try hexToColor(v.string);
        if (obj.get("surface")) |v| colors.surface = try hexToColor(v.string);
        if (obj.get("surface_alt")) |v| colors.surface_alt = try hexToColor(v.string);
        if (obj.get("border")) |v| colors.border = try hexToColor(v.string);
        if (obj.get("prompt")) |v| colors.prompt = try hexToColor(v.string);
        return colors;
    }

    fn hexToColor(hex: []const u8) !Color {
        if (hex.len < 7 or hex[0] != '#') return error.InvalidColor;
        return std.fmt.parseInt(Color, hex[1..], 16) catch error.InvalidColor;
    }
};
