const Interception = @This();
const std = @import("std");
const nt = @import("nt.zig");

address: usize,
previous_bytes: [Trampoline.size]u8,

const Trampoline = packed struct(u96) {
    pub const size = 12;

    mov_prefix: u16 = 0xB848,
    address: u64,
    push: u8 = 0x50,
    ret: u8 = 0xC3,
};

pub const Preserved = struct {
    interception: Interception,
    original_fn_entry: usize,

    pub fn replace(
        syscall: *nt.Syscall,
        address: usize,
        comptime replacementFn: anytype,
        preserve_bytes: usize,
    ) !Preserved {
        const w = std.os.windows;
        var preserved: Preserved = undefined;

        var region_size: w.SIZE_T = 4096;
        var maybe_base_address: ?[*]u8 = null;
        switch (w.ntdll.NtAllocateVirtualMemory(
            w.current_process,
            @ptrCast(&maybe_base_address),
            0,
            &region_size,
            .{ .COMMIT = true, .RESERVE = true },
            .{ .READWRITE = true },
        )) {
            .SUCCESS => {},
            else => |status| return syscall.fail(error.AllocateVirtualMemoryFailed, status),
        }

        const base_address = maybe_base_address.?;
        @memcpy(base_address[0..preserve_bytes], @as([*]u8, @ptrFromInt(address))[0..preserve_bytes]);
        const entry_trampoline: Trampoline = .{ .address = address + preserve_bytes };

        @memcpy(
            base_address[preserve_bytes..][0..Trampoline.size],
            @as([*]const u8, @ptrCast(&entry_trampoline))[0..Trampoline.size],
        );

        _ = try nt.Protection.rx.swap(syscall, @intFromPtr(base_address), preserve_bytes + Trampoline.size);

        preserved.interception = try .replace(syscall, address, replacementFn);
        preserved.original_fn_entry = @intFromPtr(base_address);

        return preserved;
    }
};

pub fn replace(syscall: *nt.Syscall, address: usize, comptime replacementFn: anytype) !Interception {
    var int: Interception = undefined;
    int.address = address;
    @memcpy(&int.previous_bytes, @as(*const [Trampoline.size]u8, @ptrFromInt(address)));

    const trampoline: Trampoline = .{ .address = @intFromPtr(&replacementFn) };

    try nt.writeExecutable(
        syscall,
        address,
        @as([*]const u8, @ptrCast(&trampoline))[0..Trampoline.size],
    );

    return int;
}

pub fn revert(int: *const Interception, syscall: *nt.Syscall) !void {
    try nt.writeExecutable(syscall, int.address, &int.previous_bytes);
}
