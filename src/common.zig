const std = @import("std");

pub fn fatal(comptime fmt: [:0]const u8, args: anytype) noreturn {
    const w = std.os.windows;

    const lpfnMessageBoxA = *const fn (
        ?w.HWND,
        ?w.LPCSTR,
        ?w.LPCSTR,
        w.UINT,
    ) callconv(.winapi) w.INT;

    var errmsg_buf: [1024]u8 = undefined;

    if (std.mem.printSentinel(&errmsg_buf, fmt, args, 0)) |errmsg| {
        var user32: w.HANDLE = undefined;

        if (w.ntdll.LdrLoadDll(
            null, // DllPath
            null, // DllCharacteristics
            &.initZ(&.{ 'U', 's', 'e', 'r', '3', '2', '.', 'd', 'l', 'l' }), // DllName
            &user32, // DllHandle
        ) == .SUCCESS) {
            var messageBoxA: lpfnMessageBoxA = undefined;

            if (w.ntdll.LdrGetProcedureAddress(
                user32, // DllHandle
                &.init("MessageBoxA"), // ProcedureName
                0, // ProcedureNumber
                @ptrCast(&messageBoxA), // ProcedureAddress
            ) == .SUCCESS)
                _ = messageBoxA(null, errmsg, "Bloom", 0x30);
        }
    } else |_| {}

    std.process.exit(1);
}
