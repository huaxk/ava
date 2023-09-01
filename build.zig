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
        .name = "ava",
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
        exe.linkSystemLibrary("sqlite3");
        exe.linkFramework("Cocoa");
        exe.linkFramework("WebKit");

        const bundle_plist = b.addInstallFile(.{ .path = "src/Info.plist" }, "Ava.app/Info.plist");
        const bundle_ico = b.addInstallFile(.{ .path = "src/app/favicon.ico" }, "Ava.app/ava.ico");
        const bundle_metal = b.addInstallFile(.{ .path = "llama.cpp/ggml-metal.metal" }, "Ava.app/ggml-metal.metal");
        const bundle_app = b.addInstallFile(.{ .generated = exe.generated_bin.? }, "Ava.app/ava");
        b.getInstallStep().dependOn(&bundle_plist.step);
        b.getInstallStep().dependOn(&bundle_ico.step);
        b.getInstallStep().dependOn(&bundle_metal.step);
        b.getInstallStep().dependOn(&bundle_app.step);
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
    try cflags.appendSlice(&.{ "-Ofast", "-fPIC", "-DNDEBUG" });
    try cxxflags.appendSlice(&.{ "-Ofast", "-fPIC", "-DNDEBUG" });

    // TODO: windows
    if (target.getOsTag() != .windows) {
        try cflags.append("-pthread");
        try cxxflags.append("-pthread");
    }

    // Use Metal on macOS
    if (target.getOsTag() == .macos) {
        try cflags.appendSlice(&.{ "-DGGML_USE_METAL", "-DGGML_METAL_NDEBUG" });
        try cxxflags.appendSlice(&.{ "-DGGML_USE_METAL", "-DGGML_METAL_NDEBUG" });

        llama.addCSourceFiles(&.{"llama.cpp/ggml-metal.m"}, cflags.items);
        llama.linkFramework("Foundation");
        llama.linkFramework("Metal");
        llama.linkFramework("MetalKit");
        llama.linkFramework("MetalPerformanceShaders");

        // copy the *.metal file so that it can be loaded at runtime
        const copy_metal_step = b.addInstallBinFile(.{ .path = "llama.cpp/ggml-metal.metal" }, "ggml-metal.metal");
        b.getInstallStep().dependOn(&copy_metal_step.step);
    }

    llama.addIncludePath(.{ .path = "llama.cpp" });
    llama.addCSourceFiles(&.{ "llama.cpp/ggml.c", "llama.cpp/ggml-alloc.c" }, cflags.items);
    llama.addCSourceFiles(&.{"llama.cpp/llama.cpp"}, cxxflags.items);

    return llama;
}
