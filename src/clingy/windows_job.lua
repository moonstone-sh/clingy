-- Loaded as Lua data so registry projection and Quaver retain the source asset.
return [=[
using System;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
public static class ClingyJob {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct Startup { public int cb; public string reserved, desktop, title;
    public int x,y,xsize,ysize,xchars,ychars,fill,flags; public short show,reserved2;
    public IntPtr reservedPtr, input, output, error; }
  [StructLayout(LayoutKind.Sequential)] struct Info { public IntPtr process, thread; public uint pid, tid; }
  [StructLayout(LayoutKind.Sequential)] struct Basic {
    public long processTime, jobTime; public uint flags; public UIntPtr min,max;
    public uint active; public UIntPtr affinity; public uint priority,scheduling;
  }
  [StructLayout(LayoutKind.Sequential)] struct Counters { public ulong a,b,c,d,e,f; }
  [StructLayout(LayoutKind.Sequential)] struct Limits {
    public Basic basic; public Counters io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob;
  }
  delegate bool Handler(uint signal);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr CreateJobObjectW(IntPtr attributes,string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref Limits limits,uint size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool CreateProcessW(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref Startup startup,out Info info);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process,uint code);
  [DllImport("kernel32.dll")] static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
  [DllImport("kernel32.dll")] static extern bool SetConsoleCtrlHandler(Handler handler,bool add);
  [DllImport("kernel32.dll")] static extern bool GenerateConsoleCtrlEvent(uint kind,uint group);
  static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  // CRT argv encoding, independent of cmd.exe/PowerShell expansion.
  static string Quote(string value) {
    var b=new StringBuilder("\""); int slashes=0;
    foreach(char c in value) {
      if(c=='\\') { slashes++; continue; }
      if(c=='"') b.Append('\\',slashes*2+1); else b.Append('\\',slashes);
      slashes=0; b.Append(c);
    }
    b.Append('\\',slashes*2); return b.Append('"').ToString();
  }
  public static int Run(string[] argv,string cwd,IDictionary env,int grace,bool stdinEof,string lockPath,string[] cleanupFiles) {
    IntPtr job=IntPtr.Zero, block=IntPtr.Zero; Info info=new Info();
    Mutex mutex=null; bool owns=false; int stopped=0;
    Handler handler=delegate(uint signal) { Interlocked.Exchange(ref stopped,1); return true; };
    try {
      if(!String.IsNullOrEmpty(lockPath)) {
        string full=System.IO.Path.GetFullPath(lockPath).ToUpperInvariant();
        byte[] hash=System.Security.Cryptography.SHA256.Create().ComputeHash(Encoding.UTF8.GetBytes(full));
        mutex=new Mutex(false,"Local\\Clingy-"+BitConverter.ToString(hash).Replace("-",""));
        try { owns=mutex.WaitOne(0); } catch(AbandonedMutexException) { owns=true; }
        if(!owns) throw new InvalidOperationException("Another Clingy session owns "+lockPath);
      }
      job=CreateJobObjectW(IntPtr.Zero,null); Check(job!=IntPtr.Zero);
      var limits=new Limits(); limits.basic.flags=0x2000; // KILL_ON_JOB_CLOSE
      Check(SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(Limits))));
      var environment=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
      foreach(DictionaryEntry pair in Environment.GetEnvironmentVariables()) environment[(string)pair.Key]=(string)pair.Value;
      foreach(DictionaryEntry pair in env) environment[(string)pair.Key]=(string)pair.Value;
      environment["CLINGY_SUPERVISOR_PID"]=System.Diagnostics.Process.GetCurrentProcess().Id.ToString();
      var data=new StringBuilder(); foreach(var pair in environment) data.Append(pair.Key).Append('=').Append(pair.Value).Append('\0');
      data.Append('\0'); block=Marshal.StringToHGlobalUni(data.ToString());
      var command=new StringBuilder(); foreach(string value in argv) { if(command.Length>0) command.Append(' '); command.Append(Quote(value)); }
      var startup=new Startup(); startup.cb=Marshal.SizeOf(typeof(Startup)); startup.flags=0x100;
      startup.input=GetStdHandle(-10); startup.output=GetStdHandle(-11); startup.error=GetStdHandle(-12);
      // Suspend before assigning ownership: a child cannot spawn outside the job.
      Check(CreateProcessW(null,command,IntPtr.Zero,IntPtr.Zero,true,0x604,block,cwd,ref startup,out info));
      if(!AssignProcessToJobObject(job,info.process)) { int error=Marshal.GetLastWin32Error(); TerminateProcess(info.process,1); throw new Win32Exception(error); }
      Check(ResumeThread(info.thread)!=0xffffffff);
      Check(SetConsoleCtrlHandler(handler,true));
      Task<int> input=stdinEof ? Task.Run(delegate { return Console.In.Read(); }) : null;
      while(WaitForSingleObject(info.process,50)==258) {
        if(input!=null && input.IsCompleted) {
          if(input.IsFaulted || input.Result<0) Interlocked.Exchange(ref stopped,1);
          else input=Task.Run(delegate { return Console.In.Read(); });
        }
        if(Interlocked.CompareExchange(ref stopped,0,0)!=0) {
          GenerateConsoleCtrlEvent(1,info.pid); // CTRL_BREAK to the owned group
          if(WaitForSingleObject(info.process,(uint)grace)==258) TerminateJobObject(job,130);
          WaitForSingleObject(info.process,5000); return 130;
        }
      }
      uint code; Check(GetExitCodeProcess(info.process,out code)); return unchecked((int)code);
    } finally {
      SetConsoleCtrlHandler(handler,false);
      if(job!=IntPtr.Zero) CloseHandle(job); // also reaps surviving descendants
      if(info.thread!=IntPtr.Zero) CloseHandle(info.thread);
      if(info.process!=IntPtr.Zero) CloseHandle(info.process);
      if(block!=IntPtr.Zero) Marshal.FreeHGlobal(block);
      if(owns || (String.IsNullOrEmpty(lockPath) && info.process!=IntPtr.Zero)) {
        foreach(string path in cleanupFiles) { try { System.IO.File.Delete(path); } catch(System.IO.IOException) {} }
      }
      if(owns) mutex.ReleaseMutex(); if(mutex!=null) mutex.Dispose();
      GC.KeepAlive(handler);
    }
  }
}
]=]
