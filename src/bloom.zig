const std = @import("std");
const mem = std.mem;
const utf8ToUtf16LeStringLiteral = std.unicode.utf8ToUtf16LeStringLiteral;
const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const LPVOID = std.os.windows.LPVOID;
const HANDLE = std.os.windows.HANDLE;
const HRESULT = u32;
const HINSTANCE = std.os.windows.HINSTANCE;

const common = @import("common.zig");
const fatal = common.fatal;

const nt = @import("nt.zig");
const Interception = @import("Interception.zig");
const offsets = @import("offsets");
const overrides = @import("overrides");

const log = std.log.scoped(.bloom);

extern "kernel32" fn AllocConsole() callconv(.winapi) void;

const CreateDxgiFactory = *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT;

var startup_hook: Interception = undefined; // Populated by `DllMain`

pub export fn DllMain(
    _: HINSTANCE,
    reason: DWORD,
    _: LPVOID,
) callconv(.winapi) BOOL {
    const w = std.os.windows;

    if (reason == 1) { // DLL_PROCESS_ATTACH
        AllocConsole();

        var dxgi: HANDLE = undefined;
        switch (w.ntdll.LdrLoadDll(
            null, // DllPath
            null, // DllCharacteristics
            &.initZ(&.{ 'd', 'x', 'g', 'i', '.', 'd', 'l', 'l' }),
            &dxgi,
        )) {
            .SUCCESS => {},
            else => |status| fatal("Init failed, couldn't load dxgi.dll ({t})", .{status}),
        }

        var create_dxgi_factory: usize = undefined;
        switch (w.ntdll.LdrGetProcedureAddress(
            dxgi,
            &.init("CreateDXGIFactory"),
            0, // ProcedureNumber
            @ptrCast(&create_dxgi_factory),
        )) {
            .SUCCESS => {},
            else => |status| fatal("Init failed, couldn't get CreateDXGIFactory address ({t})", .{status}),
        }

        var syscall: nt.Syscall = .init;
        startup_hook = Interception.replace(
            &syscall,
            create_dxgi_factory,
            createDxgiFactoryReplacement,
        ) catch |err| switch (err) {
            error.ProtectVirtualMemoryFail => fatal(
                "Init failed, couldn't intercept CreateDXGIFactory ({t})",
                .{syscall.status},
            ),
        };
    }

    return .TRUE;
}

fn createDxgiFactoryReplacement(riid: *anyopaque, factory: *anyopaque) callconv(.winapi) HRESULT {
    var syscall: nt.Syscall = .init;
    startup_hook.revert(&syscall) catch |err| switch (err) {
        error.ProtectVirtualMemoryFail => fatal(
            "Startup failed, couldn't revert CreateDXGIFactory hook ({t})",
            .{syscall.status},
        ),
    };

    startup(&syscall) catch |err|
        fatal("Startup failed: {t} (NTSTATUS: {t})", .{ err, syscall.status });

    const createDxgiFactory: CreateDxgiFactory = @ptrFromInt(startup_hook.address);
    return createDxgiFactory(riid, factory);
}

const BuildTime = BuildTime: {
    const names = @typeInfo(@TypeOf(offsets)).@"struct".field_names;
    var values: [names.len]u32 = undefined;

    for (&values, names) |*value, name|
        value.* = std.fmt.parseInt(u32, name, 10) catch
            @compileError("bad build time: " ++ name);

    break :BuildTime @Enum(u32, .exhaustive, names, &values);
};

var stringFromCStr: *const fn (
    dst: *anyopaque,
    src: [*:0]const u8,
) callconv(.c) void = undefined; // Populated by `startup`

var get_ini_config_hook: Interception.Preserved = undefined; // Populated by `startup`

fn startup(syscall: *nt.Syscall) !void {
    const w = std.os.windows;
    const base: usize = @intFromPtr(w.peb().ImageBaseAddress);

    const pe_header_offset: *u32 = @ptrFromInt(base + 0x3C);
    const timestamp: *u32 = @ptrFromInt(base + pe_header_offset.* + 8);
    const build_time = std.enums.fromInt(BuildTime, timestamp.*) orelse
        fatal("Unsupported client version: {d}", .{timestamp.*});

    switch (build_time) {
        inline else => |build_time_comptime| {
            const build_offsets = @field(offsets, @tagName(build_time_comptime));

            stringFromCStr = @ptrFromInt(base + build_offsets.string_from_cstr);
            _ = try Interception.replace(syscall, base + build_offsets.launch_key_check, launchKeyCheckStub);
            _ = try Interception.replace(syscall, base + build_offsets.get_login_host, getLoginHostReplacement);
            get_ini_config_hook =
                try .replace(syscall, base + build_offsets.get_ini_config, getIniConfigReplacement, 15);
        },
    }
}

const FString = opaque {
    /// Does not include 0-terminator.
    pub fn slice(string: *const FString) []const u16 {
        // `len` includes 0-terminator.
        const len: *u32 = @ptrFromInt(@intFromPtr(string) + 8);
        return @as(*align(1) const [*]const u16, @ptrCast(string)).*[0 .. len.* - 1];
    }
};

fn launchKeyCheckStub(_: usize) callconv(.c) bool {
    return true;
}

fn getLoginHostReplacement(dst: *anyopaque) callconv(.c) *anyopaque {
    stringFromCStr(dst, "http://127.0.0.1:30001/");
    return dst;
}

fn getIniConfigReplacement(
    dst: *FString,
    config_name: *FString,
    section: *FString,
    field: *FString,
    directory_type: u32,
) callconv(.c) *FString {
    const overrides_info = @typeInfo(@TypeOf(overrides)).@"struct";

    inline for (
        overrides_info.field_names,
        overrides_info.field_types,
    ) |file_override_name, FileOverrideType| {
        if (mem.eql(u16, config_name.slice(), utf8ToUtf16LeStringLiteral(file_override_name))) {
            const file_override_info = @typeInfo(FileOverrideType).@"struct";
            inline for (
                file_override_info.field_names,
                file_override_info.field_types,
            ) |section_override_name, SectionOverrideType| {
                if (mem.eql(u16, section.slice(), utf8ToUtf16LeStringLiteral(section_override_name))) {
                    inline for (@typeInfo(SectionOverrideType).@"struct".field_names) |field_override| {
                        if (mem.eql(u16, field.slice(), utf8ToUtf16LeStringLiteral(field_override))) {
                            stringFromCStr(dst, @field(@field(
                                @field(overrides, file_override_name),
                                section_override_name,
                            ), field_override));
                            return dst;
                        }
                    }
                }
            }
        }
    }

    const getIniConfig: *const fn (*FString, *FString, *FString, *FString, u32) callconv(.c) *FString =
        @ptrFromInt(get_ini_config_hook.original_fn_entry);

    return getIniConfig(dst, config_name, section, field, directory_type);
}
