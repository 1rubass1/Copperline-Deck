using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class CopperlineTaskbarIdentity {
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)]
 static extern int SetCurrentProcessExplicitAppUserModelID(string id);
 [DllImport("shell32.dll")]
 static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr id);
 [StructLayout(LayoutKind.Sequential)] public struct Key {public Guid fmtid;public uint pid;}
 [StructLayout(LayoutKind.Explicit,Size=24)] public struct Value {
  [FieldOffset(0)]public ushort vt;
  [FieldOffset(8)]public IntPtr text;
 }
 [ComImport,Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface Store {
  void GetCount(out uint count);
  void GetAt(uint index,out Key key);
  void GetValue(ref Key key,out Value value);
  void SetValue(ref Key key,ref Value value);
  void Commit();
 }
 public static string SetProcess(string id){
  Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(id));
  IntPtr p;Marshal.ThrowExceptionForHR(GetCurrentProcessExplicitAppUserModelID(out p));
  try{return Marshal.PtrToStringUni(p);}finally{Marshal.FreeCoTaskMem(p);}
 }
 public static void SetShortcut(string path,string id){
  object link=Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
  try {
   var file=(IPersistFile)link;file.Load(path,2);
   var store=(Store)link;
   var key=new Key{fmtid=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),pid=5};
   var value=new Value{vt=31,text=Marshal.StringToCoTaskMemUni(id)};
   try{store.SetValue(ref key,ref value);store.Commit();file.Save(path,true);}
   finally{Marshal.FreeCoTaskMem(value.text);}
  }finally{Marshal.FinalReleaseComObject(link);}
 }
}