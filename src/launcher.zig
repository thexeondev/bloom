const std = @import("std");

const common = @import("common.zig");
const fatal = common.fatal;

const exe_name = "SilverPalaceClient-Win64-Shipping.exe";
const dll_name: [:0]const u8 = "bloom.dll";

pub fn main() void {
    const w = std.os.windows;

    var startup_info = std.mem.zeroes(w.STARTUPINFOW);
    var process_info: w.PROCESS.INFORMATION = undefined;

    if (w.kernel32.CreateProcessW(
        std.unicode.utf8ToUtf16LeStringLiteral(exe_name), // lpApplicationName
        null, // lpCommandLine
        null, // lpProcessAttributes
        null, // lpThreadAttributes
        .FALSE, // bInheritHandles
        .{ .create_suspended = true }, // dwCreationFlags
        null, // lpEnvironment
        null, // lpCurrentDirectory
        &startup_info, // lpStartupInfo
        &process_info, // lpProcessInformation
    ) == .FALSE)
        fatal(
            \\Failed to create game process.
            \\Make sure you've placed red_rose.exe in the game directory, near
        ++ exe_name, .{});
    defer _ = w.ntdll.NtClose(process_info.hProcess);

    var dll_path_ptr: ?*anyopaque = null;
    var dll_path_len: usize = dll_name.len + 1;

    switch (w.ntdll.NtAllocateVirtualMemory(
        process_info.hProcess, // ProcessHandle
        @ptrCast(&dll_path_ptr), // BaseAddress
        0, // ZeroBits
        &dll_path_len, // RegionSize
        .{ .COMMIT = true, .RESERVE = true }, // AllocationType
        .{ .READWRITE = true }, // Protect
    )) {
        .SUCCESS => {},
        else => |status| fatal(
            "NtAllocateVirtualMemory failed (NTSTATUS=0x{X})",
            .{@backingInt(status)},
        ),
    }

    switch (w.ntdll.NtWriteVirtualMemory(
        process_info.hProcess, // ProcessHandle
        dll_path_ptr, // BaseAddress
        dll_name.ptr, // Buffer
        dll_name.len + 1, // NumberOfBytesToWrite
        null, // NumberOfBytesWritten
    )) {
        .SUCCESS => {},
        else => |status| fatal(
            "NtWriteVirtualMemory failed (NTSTATUS=0x{X})",
            .{@backingInt(status)},
        ),
    }

    var kernel32_handle: w.HANDLE = undefined;
    switch (w.ntdll.LdrGetDllHandle(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'K', 'e', 'r', 'n', 'e', 'l', '3', '2', '.', 'd', 'l', 'l' }), // DllName
        &kernel32_handle, // DllHandle
    )) {
        .SUCCESS => {},
        else => |status| fatal(
            "failed to obtain kernel32.dll handle (NTSTATUS=0x{X})",
            .{@backingInt(status)},
        ),
    }

    var loadlibrary_a: *anyopaque = undefined;
    switch (w.ntdll.LdrGetProcedureAddress(
        kernel32_handle, // DllHandle
        &.init("LoadLibraryA"), // ProcedureName
        0, // ProcedureNumber
        @ptrCast(&loadlibrary_a), // ProcedureAddress
    )) {
        .SUCCESS => {},
        else => unreachable,
    }

    var loader_thread: w.HANDLE = undefined;
    switch (w.ntdll.NtCreateThreadEx(
        &loader_thread, // ThreadHandle
        w.ACCESS_MASK.Specific.Thread.ALL_ACCESS, // DesiredAccess
        &.{}, // ObjectAttributes
        process_info.hProcess, // ProcessHandle
        @ptrCast(loadlibrary_a), // StartRoutine
        dll_path_ptr, // Argument
        .NONE, // CreateFlags
        0, // ZeroBits
        .default, // StackCommit
        .default, // StackReserve
        null, // AttributeList
    )) {
        .SUCCESS => {},
        else => |status| fatal(
            "failed to create loader thread (NTSTATUS=0x{X})",
            .{@backingInt(status)},
        ),
    }
    defer _ = w.ntdll.NtClose(loader_thread);

    _ = w.ntdll.NtWaitForSingleObject(loader_thread, .FALSE, null);
    _ = w.ntdll.NtResumeThread(process_info.hThread, null);
}
