const std = @import("std");

var b: *std.Build = undefined;
var target: std.zig.CrossTarget = undefined;
var optimize: std.builtin.Mode = undefined;

pub fn build(builder: *std.Build) !void {
    b = builder;
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    const llama = try addLlama();
    const exe = try addExe(llama);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // const unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // const run_unit_tests = b.addRunArtifact(unit_tests);
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_unit_tests.step);
}

fn addExe(llama: *std.Build.Step.Compile) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = b.fmt("ava_{s}", .{@tagName(target.getCpuArch())}),
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.main_pkg_path = .{ .path = "." };
    exe.addIncludePath(.{ .path = "llama.cpp" });
    exe.addCSourceFiles(&.{"src/platform.m"}, &.{ "-std=c11", "-Werror" });

    exe.linkLibrary(llama);
    b.installArtifact(exe);

    if (target.getOsTag() == .macos) {
        useMacSDK(exe);

        exe.linkSystemLibrary("sqlite3");
        exe.linkSystemLibrary("objc");
        exe.linkFramework("Foundation");
        exe.linkFramework("CoreFoundation");
        exe.linkFramework("AppKit");
        exe.linkFramework("WebKit");

        const ibtool = b.addSystemCommand(&.{ "ibtool", "--compile" });
        const nib = ibtool.addOutputFileArg("MainMenu.nib");
        ibtool.addFileArg(.{ .path = "src/platform.xib" });
        const copy_nib = b.addInstallBinFile(nib, "MainMenu.nib");
        copy_nib.step.dependOn(&ibtool.step);
        b.getInstallStep().dependOn(&copy_nib.step);
    }

    return exe;
}

fn addLlama() !*std.Build.Step.Compile {
    const llama = b.addStaticLibrary(.{
        .name = "llama",
        .target = target,
        .optimize = .ReleaseFast, // otherwise it's too slow
    });

    var cflags = std.ArrayList([]const u8).init(b.allocator);
    try cflags.append("-std=c11");
    llama.linkLibC();

    var cxxflags = std.ArrayList([]const u8).init(b.allocator);
    try cxxflags.append("-std=c++11");
    llama.linkLibCpp();

    // shared
    try cflags.appendSlice(&.{ "-Ofast", "-fPIC", "-DNDEBUG", "-DGGML_USE_K_QUANTS" });
    try cxxflags.appendSlice(&.{ "-Ofast", "-fPIC", "-DNDEBUG" });

    // TODO: windows
    if (target.getOsTag() != .windows) {
        try cflags.append("-pthread");
        try cxxflags.append("-pthread");
    }

    // Use Metal on macOS
    if (target.getOsTag() == .macos) {
        useMacSDK(llama);

        try cflags.appendSlice(&.{ "-DGGML_USE_METAL", "-DGGML_METAL_NDEBUG" });
        try cxxflags.appendSlice(&.{ "-DGGML_USE_METAL", "-DGGML_METAL_NDEBUG" });

        llama.addCSourceFiles(&.{"llama.cpp/ggml-metal.m"}, cflags.items);
        llama.linkFramework("Foundation");
        llama.linkFramework("Metal");
        llama.linkFramework("MetalKit");
        llama.linkFramework("MetalPerformanceShaders");

        // Copy the *.metal file so that it can be loaded at runtime
        const copy_metal_step = b.addInstallBinFile(.{ .path = "llama.cpp/ggml-metal.metal" }, "ggml-metal.metal");
        b.getInstallStep().dependOn(&copy_metal_step.step);
    }

    llama.addIncludePath(.{ .path = "llama.cpp" });
    llama.addCSourceFiles(&.{ "llama.cpp/ggml.c", "llama.cpp/ggml-alloc.c", "llama.cpp/k_quants.c" }, cflags.items);
    llama.addCSourceFiles(&.{"llama.cpp/llama.cpp"}, cxxflags.items);

    return llama;
}

fn useMacSDK(step: *std.Build.Step.Compile) void {
    const macos_sdk = std.mem.trimRight(u8, b.exec(&.{ "xcrun", "--show-sdk-path" }), "\n");

    step.addSystemIncludePath(.{ .path = b.fmt("{s}/usr/include", .{macos_sdk}) });
    step.addFrameworkPath(.{ .path = b.fmt("{s}/System/Library/Frameworks", .{macos_sdk}) });
    step.addLibraryPath(.{ .path = b.fmt("{s}/usr/lib", .{macos_sdk}) });
}
