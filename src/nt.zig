const std = @import("std");
const mem = std.mem;

pub const Syscall = struct {
    status: Status,

    pub const Status = std.os.windows.NTSTATUS;

    pub const init: Syscall = .{ .status = .SUCCESS };

    pub inline fn fail(syscall: *Syscall, comptime err: anytype, status: Status) @TypeOf(err) {
        syscall.status = status;
        return err;
    }
};

pub const Protection = struct {
    page: PAGE,

    const PAGE = std.os.windows.PAGE;

    pub const rx: Protection = .{ .page = .{ .EXECUTE_READ = true } };
    pub const rwx: Protection = .{ .page = .{ .EXECUTE_READWRITE = true } };

    pub const SwapError = error{ProtectVirtualMemoryFail};

    pub fn swap(p: Protection, syscall: *Syscall, address: usize, bytes: usize) SwapError!Protection {
        const w = std.os.windows;

        const start_page = mem.alignBackward(usize, address, std.heap.page_size_min);
        const end_page = mem.alignForward(usize, address + bytes, std.heap.page_size_min);
        var start_address: ?*anyopaque = @ptrFromInt(start_page);
        var number_of_bytes = end_page - start_page;

        const current_process: w.HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
        var old_page_protection: PAGE = undefined;

        return switch (w.ntdll.NtProtectVirtualMemory(
            current_process,
            &start_address,
            &number_of_bytes,
            p.page,
            &old_page_protection,
        )) {
            .SUCCESS => .{ .page = old_page_protection },
            else => |status| syscall.fail(error.ProtectVirtualMemoryFail, status),
        };
    }
};

pub fn writeExecutable(syscall: *Syscall, address: usize, bytes: []const u8) Protection.SwapError!void {
    const old_protection = try Protection.rwx.swap(syscall, address, bytes.len);
    defer _ = old_protection.swap(syscall, address, bytes.len) catch unreachable;

    @memcpy(@as([*]u8, @ptrFromInt(address))[0..bytes.len], bytes);
}
