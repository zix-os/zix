const std = @import("std");

pub const TokenKind = enum {
    // Literals
    integer,
    float,
    string,
    string_part, // Part of an interpolated string before ${
    string_end, // Final part of an interpolated string
    path,
    uri,
    identifier,

    // Keywords
    kw_if,
    kw_then,
    kw_else,
    kw_assert,
    kw_with,
    kw_let,
    kw_in,
    kw_rec,
    kw_inherit,
    kw_or,

    // Operators and delimiters
    lparen, // (
    rparen, // )
    lbrace, // {
    rbrace, // }
    lbracket, // [
    rbracket, // ]
    semicolon, // ;
    colon, // :
    comma, // ,
    dot, // .
    ellipsis, // ...
    eq, // =
    eq_eq, // ==
    not_eq, // !=
    less, // <
    less_eq, // <=
    greater, // >
    greater_eq, // >=
    plus, // +
    minus, // -
    star, // *
    slash, // /
    concat, // ++
    and_and, // &&
    or_or, // ||
    not, // !
    question, // ?
    at, // @
    arrow, // ->
    update, // //
    dollar_brace, // ${

    // Special
    eof,
    invalid,
};

pub const TokenValue = union(enum) {
    none,
    integer: i64,
    float: f64,
    identifier: []const u8,
    string: []const u8,
    path: []const u8,
    uri: []const u8,
};

pub const Token = struct {
    kind: TokenKind,
    value: TokenValue,
    line: usize,
    column: usize,
    offset: usize,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    filename: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    line_start: usize,
    // String interpolation state
    string_depth: usize, // > 0 when inside interpolated string
    brace_depth: usize, // Tracks nested braces inside ${}
    allocated_strings: std.ArrayList([]const u8), // Track allocated strings to free
    in_indented_string: bool, // Track if current string interpolation is in indented string

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: []const u8, filename: []const u8) Self {
        return Self{
            .allocator = allocator,
            .source = source,
            .filename = filename,
            .pos = 0,
            .line = 1,
            .column = 1,
            .line_start = 0,
            .string_depth = 0,
            .brace_depth = 0,
            .allocated_strings = .empty,
            .in_indented_string = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.allocated_strings.items) |str| {
            self.allocator.free(str);
        }
        self.allocated_strings.clearAndFree(self.allocator);
    }

    pub fn nextToken(self: *Self) !Token {
        // Skip whitespace and comments
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r') {
                self.advance();
            } else if (ch == '\n') {
                self.advanceLine();
            } else if (ch == '#') {
                // Line comment
                self.advance();
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
            } else if (ch == '/' and self.peek() == '*') {
                // Block comment
                self.advance();
                self.advance();
                while (self.pos < self.source.len) {
                    if (self.source[self.pos] == '*' and self.peek() == '/') {
                        self.advance();
                        self.advance();
                        break;
                    }
                    if (self.source[self.pos] == '\n') {
                        self.advanceLine();
                    } else {
                        self.advance();
                    }
                }
            } else {
                break;
            }
        }

        const token_start = self.pos;
        const token_line = self.line;
        const token_column = self.column;

        if (self.pos >= self.source.len) {
            return Token{
                .kind = .eof,
                .value = .none,
                .line = token_line,
                .column = token_column,
                .offset = token_start,
            };
        }

        // Special handling for braces when inside string interpolation
        if (self.string_depth > 0 and self.brace_depth > 0) {
            const ch = self.source[self.pos];
            if (ch == '{') {
                self.brace_depth += 1;
                self.advance();
                return Token{ .kind = .lbrace, .value = .none, .line = token_line, .column = token_column, .offset = token_start };
            } else if (ch == '}') {
                self.brace_depth -= 1;
                if (self.brace_depth == 0) {
                    // End of interpolation, continue the string
                    self.advance();

                    const result = if (self.in_indented_string)
                        try self.lexIndentedStringContinue(token_line, token_column, token_start)
                    else
                        try self.lexStringContinue(token_line, token_column, token_start);

                    // After the continuation, restore brace_depth if needed
                    // The continuation function may have decremented string_depth
                    if (self.string_depth > 0) {
                        self.brace_depth = 1;
                    }
                    return result;
                } else {
                    self.advance();
                    return Token{ .kind = .rbrace, .value = .none, .line = token_line, .column = token_column, .offset = token_start };
                }
            }
            // For any other token, fall through to normal handling below
        }

        const ch = self.source[self.pos];

        // String literals
        if (ch == '"') {
            return try self.lexString(token_line, token_column, token_start);
        }

        // Indented strings
        if (ch == '\'') {
            if (self.peek() == '\'') {
                return try self.lexIndentedString(token_line, token_column, token_start);
            } else {
                std.debug.print("Found single quote at pos {d}, peek gives {c}\n", .{ self.pos, self.peek() });
            }
        }

        // Numbers
        if (std.ascii.isDigit(ch)) {
            return self.lexNumber(token_line, token_column, token_start);
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(ch) or ch == '_') {
            return self.lexIdentifier(token_line, token_column, token_start);
        }

        // Paths (relative or absolute)
        if ((ch == '.' or ch == '/') and self.isPathStart()) {
            return try self.lexPath(token_line, token_column, token_start);
        }

        // URIs
        if (std.ascii.isAlphabetic(ch) and self.isUriStart()) {
            return try self.lexUri(token_line, token_column, token_start);
        }

        // Two-character operators
        const next = self.peek();
        if (ch == '=' and next == '=') {
            self.advance();
            self.advance();
            return self.makeToken(.eq_eq, token_line, token_column, token_start);
        }
        if (ch == '!' and next == '=') {
            self.advance();
            self.advance();
            return self.makeToken(.not_eq, token_line, token_column, token_start);
        }
        if (ch == '<' and next == '=') {
            self.advance();
            self.advance();
            return self.makeToken(.less_eq, token_line, token_column, token_start);
        }
        if (ch == '>' and next == '=') {
            self.advance();
            self.advance();
            return self.makeToken(.greater_eq, token_line, token_column, token_start);
        }
        if (ch == '+' and next == '+') {
            self.advance();
            self.advance();
            return self.makeToken(.concat, token_line, token_column, token_start);
        }
        if (ch == '&' and next == '&') {
            self.advance();
            self.advance();
            return self.makeToken(.and_and, token_line, token_column, token_start);
        }
        if (ch == '|' and next == '|') {
            self.advance();
            self.advance();
            return self.makeToken(.or_or, token_line, token_column, token_start);
        }
        if (ch == '-' and next == '>') {
            self.advance();
            self.advance();
            return self.makeToken(.arrow, token_line, token_column, token_start);
        }
        if (ch == '/' and next == '/') {
            self.advance();
            self.advance();
            return self.makeToken(.update, token_line, token_column, token_start);
        }
        if (ch == '.' and next == '.' and self.pos + 2 < self.source.len and self.source[self.pos + 2] == '.') {
            self.advance();
            self.advance();
            self.advance();
            return self.makeToken(.ellipsis, token_line, token_column, token_start);
        }
        if (ch == '$' and next == '{') {
            self.advance();
            self.advance();
            // If we're in a string interpolation, increment brace_depth to track this inner `{`
            if (self.string_depth > 0) {
                self.brace_depth += 1;
            }
            return self.makeToken(.dollar_brace, token_line, token_column, token_start);
        }

        // Single-character tokens
        self.advance();
        return self.makeToken(switch (ch) {
            '(' => .lparen,
            ')' => .rparen,
            '{' => .lbrace,
            '}' => .rbrace,
            '[' => .lbracket,
            ']' => .rbracket,
            ';' => .semicolon,
            ':' => .colon,
            ',' => .comma,
            '.' => .dot,
            '=' => .eq,
            '<' => .less,
            '>' => .greater,
            '+' => .plus,
            '-' => .minus,
            '*' => .star,
            '/' => .slash,
            '!' => .not,
            '?' => .question,
            '@' => .at,
            else => .invalid,
        }, token_line, token_column, token_start);
    }

    fn lexString(self: *Self, line: usize, column: usize, start: usize) !Token {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        const initial_string_depth = self.string_depth;

        self.advance(); // Skip opening "

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '"') {
                self.advance();
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                // If WE started an interpolation (string_depth > initial), this ends it
                const had_interpolation = self.string_depth > initial_string_depth;
                const kind: TokenKind = if (had_interpolation) .string_end else .string;
                if (had_interpolation) {
                    self.string_depth -= 1;
                    if (self.string_depth == 0) self.in_indented_string = false;
                }
                return Token{
                    .kind = kind,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            // Check for interpolation ${
            if (ch == '$' and self.peek() == '{') {
                // Return string so far as string_part, set up state for interpolation
                self.string_depth += 1;
                self.brace_depth = 1; // Reset to 1 for this interpolation level
                self.in_indented_string = false;
                self.advance(); // Skip $
                self.advance(); // Skip {
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                return Token{
                    .kind = .string_part,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            if (ch == '\\') {
                self.advance();
                if (self.pos >= self.source.len) return error.UnterminatedString;
                const escaped = self.source[self.pos];
                self.advance();
                try buffer.append(self.allocator, switch (escaped) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '"' => '"',
                    '$' => '$',
                    else => escaped,
                });
            } else {
                try buffer.append(self.allocator, ch);
                if (ch == '\n') {
                    self.line += 1;
                    self.column = 1;
                    self.line_start = self.pos + 1;
                    self.pos += 1;
                } else {
                    self.advance();
                }
            }
        }

        return error.UnterminatedString;
    }

    /// Continue lexing a string after an interpolation expression
    fn lexStringContinue(self: *Self, line: usize, column: usize, start: usize) !Token {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '"') {
                self.advance();
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                self.string_depth -= 1;
                if (self.string_depth == 0) self.in_indented_string = false;
                return Token{
                    .kind = .string_end,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            // Check for another interpolation ${
            if (ch == '$' and self.peek() == '{') {
                // Return string so far as string_part
                self.brace_depth = 1; // Reset to 1 for this interpolation
                self.advance(); // Skip $
                self.advance(); // Skip {
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                return Token{
                    .kind = .string_part,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            if (ch == '\\') {
                self.advance();
                if (self.pos >= self.source.len) return error.UnterminatedString;
                const escaped = self.source[self.pos];
                self.advance();
                try buffer.append(self.allocator, switch (escaped) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '"' => '"',
                    '$' => '$',
                    else => escaped,
                });
            } else {
                try buffer.append(self.allocator, ch);
                if (ch == '\n') {
                    self.line += 1;
                    self.column = 1;
                    self.line_start = self.pos + 1;
                    self.pos += 1;
                } else {
                    self.advance();
                }
            }
        }

        return error.UnterminatedString;
    }

    fn lexIndentedString(self: *Self, line: usize, column: usize, start: usize) !Token {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        const initial_string_depth = self.string_depth;

        self.advance(); // Skip first '
        self.advance(); // Skip second '

        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\'' and self.peek() == '\'') {
                self.advance();
                self.advance();
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                // If WE started an interpolation (string_depth > initial), this ends it
                const had_interpolation = self.string_depth > initial_string_depth;
                const kind: TokenKind = if (had_interpolation) .string_end else .string;
                if (had_interpolation) {
                    self.string_depth -= 1;
                }
                // Always reset in_indented_string when an indented string ends
                self.in_indented_string = false;
                return Token{
                    .kind = kind,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            // Check for interpolation ${
            const ch = self.source[self.pos];
            if (ch == '$' and self.peek() == '{') {
                // Return string so far as string_part, set up state for interpolation
                self.string_depth += 1;
                self.brace_depth = 1; // Reset to 1 for this interpolation level
                self.in_indented_string = true;
                self.advance(); // Skip $
                self.advance(); // Skip {
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                return Token{
                    .kind = .string_part,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            try buffer.append(self.allocator, ch);
            if (ch == '\n') {
                self.advanceLine();
            } else {
                self.advance();
            }
        }
        return error.UnterminatedString;
    }

    /// Continue lexing an indented string after an interpolation expression
    fn lexIndentedStringContinue(self: *Self, line: usize, column: usize, start: usize) !Token {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(self.allocator);

        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\'' and self.peek() == '\'') {
                self.advance();
                self.advance();
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                self.string_depth -= 1;
                // Always reset in_indented_string when an indented string ends
                self.in_indented_string = false;
                return Token{
                    .kind = .string_end,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            // Check for another interpolation ${
            const ch = self.source[self.pos];
            if (ch == '$' and self.peek() == '{') {
                // Return string so far as string_part
                self.brace_depth = 1; // Reset to 1 for this interpolation
                self.advance(); // Skip $
                self.advance(); // Skip {
                const str = try buffer.toOwnedSlice(self.allocator);
                try self.allocated_strings.append(self.allocator, str);
                return Token{
                    .kind = .string_part,
                    .value = .{ .string = str },
                    .line = line,
                    .column = column,
                    .offset = start,
                };
            }
            try buffer.append(self.allocator, ch);
            if (ch == '\n') {
                self.advanceLine();
            } else {
                self.advance();
            }
        }
        return error.UnterminatedString;
    }

    fn lexNumber(self: *Self, line: usize, column: usize, start: usize) Token {
        var is_float = false;

        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isDigit(ch)) {
                self.advance();
            } else if (ch == '.' and !is_float and self.pos + 1 < self.source.len and
                std.ascii.isDigit(self.source[self.pos + 1]))
            {
                is_float = true;
                self.advance();
            } else if ((ch == 'e' or ch == 'E') and !is_float) {
                is_float = true;
                self.advance();
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.advance();
                }
            } else {
                break;
            }
        }

        const text = self.source[start..self.pos];

        if (is_float) {
            const val = std.fmt.parseFloat(f64, text) catch 0.0;
            return Token{
                .kind = .float,
                .value = .{ .float = val },
                .line = line,
                .column = column,
                .offset = start,
            };
        } else {
            const val = std.fmt.parseInt(i64, text, 10) catch 0;
            return Token{
                .kind = .integer,
                .value = .{ .integer = val },
                .line = line,
                .column = column,
                .offset = start,
            };
        }
    }

    fn lexIdentifier(self: *Self, line: usize, column: usize, start: usize) Token {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '\'') {
                self.advance();
            } else {
                break;
            }
        }

        const text = self.source[start..self.pos];

        const kind: TokenKind = if (std.mem.eql(u8, text, "if"))
            .kw_if
        else if (std.mem.eql(u8, text, "then"))
            .kw_then
        else if (std.mem.eql(u8, text, "else"))
            .kw_else
        else if (std.mem.eql(u8, text, "assert"))
            .kw_assert
        else if (std.mem.eql(u8, text, "with"))
            .kw_with
        else if (std.mem.eql(u8, text, "let"))
            .kw_let
        else if (std.mem.eql(u8, text, "in"))
            .kw_in
        else if (std.mem.eql(u8, text, "rec"))
            .kw_rec
        else if (std.mem.eql(u8, text, "inherit"))
            .kw_inherit
        else if (std.mem.eql(u8, text, "or"))
            .kw_or
        else
            .identifier;

        return Token{
            .kind = kind,
            .value = if (kind == .identifier) .{ .identifier = text } else .none,
            .line = line,
            .column = column,
            .offset = start,
        };
    }

    fn lexPath(self: *Self, line: usize, column: usize, start: usize) !Token {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '/' or ch == '.' or
                ch == '_' or ch == '-' or ch == '+')
            {
                self.advance();
            } else {
                break;
            }
        }

        const text = self.source[start..self.pos];
        const path = try self.allocator.dupe(u8, text);
        try self.allocated_strings.append(self.allocator, path);

        return Token{
            .kind = .path,
            .value = .{ .path = path },
            .line = line,
            .column = column,
            .offset = start,
        };
    }

    fn lexUri(self: *Self, line: usize, column: usize, start: usize) !Token {
        // Scheme
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '+' or ch == '-' or ch == '.') {
                self.advance();
            } else if (ch == ':') {
                self.advance();
                break;
            } else {
                break;
            }
        }

        // Rest of URI
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '%' or ch == '/' or ch == '?' or
                ch == ':' or ch == '@' or ch == '&' or ch == '=' or ch == '+' or
                ch == '$' or ch == ',' or ch == '-' or ch == '_' or ch == '.' or
                ch == '!' or ch == '~' or ch == '*' or ch == '\'' or ch == '(' or ch == ')')
            {
                self.advance();
            } else {
                break;
            }
        }

        const text = self.source[start..self.pos];
        const uri = try self.allocator.dupe(u8, text);
        try self.allocated_strings.append(self.allocator, uri);

        return Token{
            .kind = .uri,
            .value = .{ .uri = uri },
            .line = line,
            .column = column,
            .offset = start,
        };
    }

    fn isPathStart(self: *Self) bool {
        const ch = self.source[self.pos];
        // A single '/' is the division operator, not a path
        // Paths must be like /foo or ./ or ../
        if (ch == '/' and self.pos + 1 < self.source.len) {
            const next = self.source[self.pos + 1];
            return std.ascii.isAlphanumeric(next) or next == '_' or next == '-' or next == '.';
        }
        if (ch == '.' and self.pos + 1 < self.source.len) {
            const next = self.source[self.pos + 1];
            // Exclude `...` (ellipsis) - it's not a path
            if (next == '.' and self.pos + 2 < self.source.len and self.source[self.pos + 2] == '.') {
                return false;
            }
            return next == '/' or next == '.';
        }
        return false;
    }

    fn isUriStart(self: *Self) bool {
        var i = self.pos;
        // Check for scheme like http:// or https://
        while (i < self.source.len) {
            const ch = self.source[i];
            if (ch == ':') {
                return i > self.pos and i + 2 < self.source.len and
                    self.source[i + 1] == '/' and self.source[i + 2] == '/';
            }
            if (!std.ascii.isAlphanumeric(ch) and ch != '+' and ch != '-' and ch != '.') {
                return false;
            }
            i += 1;
            if (i - self.pos > 20) return false; // Reasonable scheme length limit
        }
        return false;
    }

    fn makeToken(self: *Self, kind: TokenKind, line: usize, column: usize, start: usize) Token {
        _ = self;
        return Token{
            .kind = kind,
            .value = .none,
            .line = line,
            .column = column,
            .offset = start,
        };
    }

    fn advance(self: *Self) void {
        self.pos += 1;
        self.column += 1;
    }

    fn advanceLine(self: *Self) void {
        self.pos += 1;
        self.line += 1;
        self.column = 1;
        self.line_start = self.pos;
    }

    fn peek(self: *Self) u8 {
        if (self.pos + 1 < self.source.len) {
            return self.source[self.pos + 1];
        }
        return 0;
    }
};

// Tests
test "lexer basic tokens" {
    const allocator = std.testing.allocator;
    const source = "( ) { } [ ] ; : , . = + - * /";
    var lex = Lexer.init(allocator, source, "test");
    defer lex.deinit();

    const expected = [_]TokenKind{
        .lparen,    .rparen, .lbrace, .rbrace, .lbracket, .rbracket,
        .semicolon, .colon,  .comma,  .dot,    .eq,       .plus,
        .minus,     .star,   .slash,
    };

    for (expected) |kind| {
        const token = try lex.nextToken();
        try std.testing.expectEqual(kind, token.kind);
    }
}

test "lexer numbers" {
    const allocator = std.testing.allocator;
    const source = "42 3.14 1e10";
    var lex = Lexer.init(allocator, source, "test");
    defer lex.deinit();

    const tok1 = try lex.nextToken();
    try std.testing.expectEqual(TokenKind.integer, tok1.kind);
    try std.testing.expectEqual(@as(i64, 42), tok1.value.integer);

    const tok2 = try lex.nextToken();
    try std.testing.expectEqual(TokenKind.float, tok2.kind);

    const tok3 = try lex.nextToken();
    try std.testing.expectEqual(TokenKind.float, tok3.kind);
}

test "lexer keywords" {
    const allocator = std.testing.allocator;
    const source = "if then else let in rec";
    var lex = Lexer.init(allocator, source, "test");
    defer lex.deinit();

    try std.testing.expectEqual(TokenKind.kw_if, (try lex.nextToken()).kind);
    try std.testing.expectEqual(TokenKind.kw_then, (try lex.nextToken()).kind);
    try std.testing.expectEqual(TokenKind.kw_else, (try lex.nextToken()).kind);
    try std.testing.expectEqual(TokenKind.kw_let, (try lex.nextToken()).kind);
    try std.testing.expectEqual(TokenKind.kw_in, (try lex.nextToken()).kind);
    try std.testing.expectEqual(TokenKind.kw_rec, (try lex.nextToken()).kind);
}
