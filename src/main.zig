const std = @import("std");
const clap = @import("clap.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const MemoryRegion = struct {
  start: u64,
  end: u64,
};

pub fn parseLine(line: []const u8) !MemoryRegion {
  var start: u64 = undefined;
  var end: u64 = undefined;
  var i: usize = 0;
  var j: usize = 0;

  while (i < line.len) {
    if (line[i] == '-') {
      start = try std.fmt.parseInt(u64, line[0..i], 16);
      j = i + 1;
    }
    if (line[i] == ' ') {
      end = try std.fmt.parseInt(u64, line[j..i], 16);
      break;
    }
    i += 1;
  }
  return MemoryRegion { .start = start, .end = end };
}

pub fn main() !u8 {
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer _ = gpa.deinit();
  const allocator = gpa.allocator();

  const args = try std.process.argsAlloc(allocator);
  defer std.process.argsFree(allocator, args);

  const parsedArgs = clap.parser(clap.ArgDescriptor{
    .name = "vmmap",
    .description = "Retrieve a memory region from an address",
    .withHelp = true,
    .version = "0.1.0",
    .expectArgs = &[_][]const u8{ "pid", "address" },
    .options = &[_]clap.OptionDescription{},
  }).parse(args);

  const pid = parsedArgs.arguments.items[0];
  // if 0x prefix is present, ignore it
  const address_param = if (parsedArgs.arguments.items[1][0] == '0'
    and parsedArgs.arguments.items[1][1] == 'x')
    parsedArgs.arguments.items[1][2..]
  else
    parsedArgs.arguments.items[1];

  if (address_param.len > 12) {
    try stderr.print("error: address must be 48bits maximum ({} bits given)", .{ address_param.len * 4 });
    return 1;
  }

  const address = try std.fmt.parseInt(i128, address_param, 16);

  var buffer: [256]u8 = undefined;
  const maps_file = try std.fmt.bufPrint(&buffer, "/proc/{s}/maps", .{ pid });

  const file = try std.fs.cwd().openFile(maps_file, .{});
  defer file.close();

  var buf_reader = std.io.bufferedReader(file.reader());
  const reader = buf_reader.reader();

  var line = std.ArrayList(u8).init(allocator);
  defer line.deinit();

  const writer = line.writer();
  while (reader.streamUntilDelimiter(writer, '\n', null)) {
    // Clear the line so we can reuse it.
    defer line.clearRetainingCapacity();
    // std.debug.print("{s}\n", .{ line.items });
    const memregion = try parseLine(line.items);
    if (address >= memregion.start and address <= memregion.end) {
      try stdout.print("{s}\n", .{ line.items });
      return 0;
    }
  } else |err| switch (err) {
    error.EndOfStream => {}, // end of file
    else => return err, // Propagate error
  }

  try stderr.print("error: address 0x{x} is not map into the processor memory space\n", .{ address });
  return 1;
}
