# The job object a test run uses to end the processes it starts: the one home of the job type, and of the job a direct run makes.
# test\run.ps1 makes one job per child file (Add-SuiteJobType, [SuiteJob]) and stops it with the child, so stopping the suite ends every
# process a child started. A test file run directly has no such job: killed hard, its finally never runs, and the headless Edge and the
# servers it started stay and hold files and ports for the next run. Enter-DirectRunJob gives the file a job of its own.
# test\run.ps1 and each test file that starts headless Edge dot-sources this file and calls Enter-DirectRunJob as a top-level statement
# before it starts anything. test\direct-run.ps1 checks the call in each file and its effect. test\suite-kill.ps1 dot-sources this file
# too, because it takes run.ps1's functions from the parse tree and Start-Suite needs Add-SuiteJobType.

# The job object type: P/Invoke in a new type of its own. A job made here ends its processes when it is stopped, and when the process
# that made it ends, so a child cannot outlive the run.
function Add-SuiteJobType {
  if ('SuiteJob' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SuiteJob {
  const int ExtendedLimitInfo = 9;
  const uint KillOnJobClose = 0x2000;
  [StructLayout(LayoutKind.Sequential)] public struct BasicLimit {
    public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
    public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
  [StructLayout(LayoutKind.Sequential)] public struct IoCounters { public ulong A, B, C, D, E, F; }
  [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimit {
    public BasicLimit Basic; public IoCounters Io; public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit;
    public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint exitCode);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr handle);
  // A job whose close ends every process in it. Zero when it could not be made.
  public static IntPtr Create() {
    IntPtr job = CreateJobObject(IntPtr.Zero, null);
    if (job == IntPtr.Zero) return IntPtr.Zero;
    ExtendedLimit info = new ExtendedLimit();
    info.Basic.LimitFlags = KillOnJobClose;
    int size = Marshal.SizeOf(typeof(ExtendedLimit));
    IntPtr ptr = Marshal.AllocHGlobal(size);
    try {
      Marshal.StructureToPtr(info, ptr, false);
      if (!SetInformationJobObject(job, ExtendedLimitInfo, ptr, (uint)size)) { CloseHandle(job); return IntPtr.Zero; }
    } finally { Marshal.FreeHGlobal(ptr); }
    return job;
  }
  public static bool Assign(IntPtr job, IntPtr process) { return AssignProcessToJobObject(job, process); }
  // Ends every process in the job, then closes it.
  public static void Stop(IntPtr job) {
    if (job == IntPtr.Zero) return;
    TerminateJobObject(job, 1);
    CloseHandle(job);
  }
}
'@
}

# Puts this process in a job that ends with it, so a hard kill of the file also ends every process it started (Edge, servers). The job's
# handle stays open until the process ends: closing it would end the job early, so it is never closed, and no child gets it (the handle
# is not inheritable). Under the suite (TILE_TEST_SUITE is 1, which test\run.ps1 sets for its children) the suite's own job already
# holds the file, so none is made and the type is not compiled. A job that cannot be made or joined prints one WARN line, and the file
# then runs as it did before, with no job. The job ends the processes at once, but a killed Edge tree can take seconds to go on a loaded
# machine (test\direct-run.ps1 says how long).
function Enter-DirectRunJob {
  if ($env:TILE_TEST_SUITE) { return }
  Add-SuiteJobType
  $job = [SuiteJob]::Create()
  if ($job.ToInt64() -eq 0 -or -not [SuiteJob]::Assign($job, [Diagnostics.Process]::GetCurrentProcess().Handle)) {
    'WARN  direct run: no job object for this file, so a hard kill of it leaves its Edge and servers running'
  }
}
