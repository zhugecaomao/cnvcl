{******************************************************************************}
{                       CnPack For Delphi/C++Builder                           }
{                     中国人自己的开放源码第三方开发包                         }
{                   (C)Copyright 2001-2020 CnPack 开发组                       }
{                   ------------------------------------                       }
{                                                                              }
{            本开发包是开源的自由软件，您可以遵照 CnPack 的发布协议来修        }
{        改和重新发布这一程序。                                                }
{                                                                              }
{            发布这一开发包的目的是希望它有用，但没有任何担保。甚至没有        }
{        适合特定目的而隐含的担保。更详细的情况请参阅 CnPack 发布协议。        }
{                                                                              }
{            您应该已经和开发包一起收到一份 CnPack 发布协议的副本。如果        }
{        还没有，可访问我们的网站：                                            }
{                                                                              }
{            网站地址：http://www.cnpack.org                                   }
{            电子邮件：master@cnpack.org                                       }
{                                                                              }
{******************************************************************************}

unit CnRtlUtils;
{* |<PRE>
================================================================================
* 软件名称：CnDebugger
* 单元名称：CnDebug 相关的运行期工具单元
* 单元作者：刘啸（liuxiao@cnpack.org）
* 备    注：该单元实现了部分 CnDebugger 所需的 Module/Stack 相关内容
*           部分内容引用了 JCL
* 开发平台：PWin7 + Delphi 5
* 兼容测试：Win32/Win64
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2020.05.04
*               实现当前 exe 内改写 IAT 的方式 Hook API，同时支持 32/64。
*               当模块内的 OriginalFirstThunk 有效时根据函数名来搜索 IAT
*               当模块内的 OriginalFirstThunk 为 0 时直接用地址来搜索 IAT
*           2020.05.04
*               实现当前堆栈的两种调用地址追踪实现，同时支持 32/64，其中 StackWalk64 有问题
*           2020.04.26
*               创建单元,实现功能
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, Classes, Windows, Contnrs, TLHelp32, Psapi, Imagehlp;

type
  PCnStackFrame = ^TCnStackFrame;
  TCnStackFrame = record
    CallersEBP: Pointer;
    CallerAdr: Pointer;
  end;

  TCnModuleInfo = class(TObject)
  {* 描述一个模块信息，exe 或 dll 或 bpl 等，支持 32/64 位}
  private
    FSize: Cardinal;
    FStartAddr: Pointer;
    FEndAddr: Pointer;
    FBaseName: string;
    FFullName: string;
    FIsDelphi: Boolean;
    FHModule: HMODULE;
  public
    function ToString: string; {$IFDEF OBJECT_HAS_TOSTRING} override; {$ENDIF}

    property BaseName: string read FBaseName write FBaseName;
    {* 模块文件名}
    property FullName: string read FFullName write FFullName;
    {* 模块完整路径名}
    property Size: Cardinal read FSize write FSize;
    {* 模块大小}
    property HModule: HMODULE read FHModule write FHModule;
    {* 模块 Handle，也就是 AllocationBase，一般等于 StartAddr}
    property StartAddr: Pointer read FStartAddr write FStartAddr;
    {* 模块在本进程地址空间的起始地址，也即 lpBaseOfDll}
    property EndAddr: Pointer read FEndAddr write FEndAddr;
    {* 模块在本进程地址空间的结束地址}
    property IsDelphi: Boolean read FIsDelphi write FIsDelphi;
    {* 是否是 Delphi 模块，指通过 System.pas 中的 LibModuleList 注册过的}
  end;

  TCnModuleInfoList = class(TObjectList)
  {* 描述本进程内的所有模块信息，exe 或 dll 或 bpl 等，支持 32/64 位}
  private
    FDelphiOnly: Boolean;
    function GetItems(Index: Integer): TCnModuleInfo;
    function GetModuleFromAddress(Addr: Pointer): TCnModuleInfo;
    function AddModule(PH: THandle; MH: HMODULE): TCnModuleInfo;
    procedure CheckDelphiModule(Info: TCnModuleInfo);
  protected
    procedure BuildModulesList;
    function CreateItemForAddress(Addr: Pointer; AIsDelphi: Boolean): TCnModuleInfo;
  public
    constructor Create(ADelphiOnly: Boolean = False); virtual;
    destructor Destroy; override;

    procedure DumpToStrings(List: TStrings);

    function IsValidModuleAddress(Addr: Pointer): Boolean;
    {* 判断某地址是否属于本进程内一个模块内的地址}
    function IsDelphiModuleAddress(Addr: Pointer): Boolean;
    {* 判断某地址是否属于本进程内一个 Delphi 模块内的地址}
    property Items[Index: Integer]: TCnModuleInfo read GetItems;
  end;

  TCnStackInfo = class
  {* 描述一层堆栈调用地址，支持 32/64 位}
  private
    FCallerAddr: Pointer;
  public
    property CallerAddr: Pointer read FCallerAddr write FCallerAddr;
  end;

  TCnStackInfoList = class(TObjectList)
  {* 描述对象实例化时当前调用栈的多层地址，支持 32/64 位}
  private
    FModuleList: TCnModuleInfoList;
    function GetItems(Index: Integer): TCnStackInfo;
    procedure TraceStackFrames;
  public
    constructor Create(OnlyDelphi: Boolean = False);
    destructor Destroy; override;

    procedure DumpToStrings(List: TStrings);

    property Items[Index: Integer]: TCnStackInfo read GetItems; default;
  end;

// ================= 进程内指定模块用改写 IAT 表的方式 Hook API ================

function CnHookImportAddressTable(const ImportModuleName, ImportFuncName: string;
  out OldAddress: Pointer; NewAddress: Pointer; ModuleHandle: THandle = 0): Boolean;
{* 进程内改写指定模块的导入表以达到 Hook 该模块内对外部模块的函数调用的目的，支持 32/64 位

  ImportModuleName: 待 Hook 的函数所在的模块名，不是全路径名，如 user32.dll
  ImportFuncName:   待 Hook 的函数名称，如 MessageBoxA
  OldAddress:       Hook 成功后供返回的旧地址，无需传入值，由调用者保存，供 UnHook 时恢复
  NewAddress:       新函数的地址，如 @MyMessageBoxA
  ModuleHandle:     待 Hook 的模块，可以用 GetModuleHandle 根据需要获得，
                    如传 0，表示 Hook 本进程的 exe 内

  返回值 True 表示 Hook 成功
  注：对于同一个模块内，Hook 同一个外部模块的同一个函数时，要控制不能重复 Hook，以及和 UnHook 要严格配对
}

function CnUnHookImportAddressTable(const ImportModuleName, ImportFuncName: string;
  OldAddress, NewAddress: Pointer; ModuleHandle: THandle = 0): Boolean;
{* 进程内改写指定模块的导入表 Hook 的还原，支持 32/64 位

  ImportModuleName: 待 Hook 的函数所在的模块名，不是全路径名，如 user32.dll
  ImportFuncName:   待 Hook 的函数名称，如 MessageBoxA
  OldAddress:       Hook 成功后返回的旧地址
  NewAddress:       新函数的地址，如 @MyMessageBoxA
  ModuleHandle:     待 Hook 的模块，可以用 GetModuleHandle 根据需要获得，
                    如传 0，表示 Hook 本进程的 exe 内

  返回值 True 表示 UnHook 成功
  注：对于同一个模块内，Hook 同一个外部模块的同一个函数时，要控制不能重复 UnHook，以及和 Hook 要严格配对
}

implementation

const
{$IFDEF WIN64}
  HEX_FMT = '$%16.16x';
{$ELSE}
  HEX_FMT = '$%8.8x';
{$ENDIF}

  MODULE_INFO_FMT = 'HModule: ' + HEX_FMT + ' Base: ' + HEX_FMT + ' End: ' +
    HEX_FMT + ' Size: ' + HEX_FMT + ' IsDelphiModule %d. Name: %s - %s';
  STACK_INFO_FMT = 'Caller: ' + HEX_FMT;

  MAX_STACK_COUNT = 1024;
  ImagehlpLib = 'IMAGEHLP.DLL';
  IMAGE_ORDINAL_FLAG = LongWord($80000000);

type
{$IFDEF WIN64}
  TCnNativeUInt = NativeUInt;
{$ELSE}
  TCnNativeUInt = Cardinal;
{$ENDIF}

  TRtlCaptureStackBackTrace = function (FramesToSkip: LongWord; FramesToCapture: LongWord;
    var BackTrace: Pointer; BackTraceHash: PLongWord): Word; stdcall;
  TRtlCaptureContext = procedure (ContextRecord: PContext); stdcall;

{$IFDEF WIN64}
  // Types of Address
  LPADDRESS64 = ^ADDRESS64;
  {$EXTERNALSYM PADDRESS64}
  _tagADDRESS64 = record
    Offset: DWORD64;
    Segment: WORD;
    Mode: ADDRESS_MODE;
  end;
  {$EXTERNALSYM _tagADDRESS64}
  ADDRESS64 = _tagADDRESS64;
  {$EXTERNALSYM ADDRESS64}
  TAddress64 = ADDRESS64;
  PAddress64 = LPADDRESS64;

  // Types of KDHelp
  PKDHELP64 = ^KDHELP64;
  {$EXTERNALSYM PKDHELP64}
  _KDHELP64 = record
    Thread: DWORD64;
    ThCallbackStack: DWORD;
    ThCallbackBStore: DWORD;
    NextCallback: DWORD;
    FramePointer: DWORD;
    KiCallUserMode: DWORD64;
    KeUserCallbackDispatcher: DWORD64;
    SystemRangeStart: DWORD64;
    Reserved: array [0..7] of DWORD64;
  end;
  {$EXTERNALSYM _KDHELP64}
  KDHELP64 = _KDHELP64;
  {$EXTERNALSYM KDHELP64}
  TKdHelp64 = KDHELP64;

  // Types of StackFrame64
  LPSTACKFRAME64 = ^STACKFRAME64;
  {$EXTERNALSYM LPSTACKFRAME64}
  _tagSTACKFRAME64 = record
    AddrPC: ADDRESS64; // program counter
    AddrReturn: ADDRESS64; // return address
    AddrFrame: ADDRESS64; // frame pointer
    AddrStack: ADDRESS64; // stack pointer
    AddrBStore: ADDRESS64; // backing store pointer
    FuncTableEntry: PVOID; // pointer to pdata/fpo or NULL
    Params: array [0..3] of DWORD64; // possible arguments to the function
    Far: BOOL; // WOW far call
    Virtual: BOOL; // is this a virtual frame?
    Reserved: array [0..2] of DWORD64;
    KdHelp: KDHELP64;
  end;
  {$EXTERNALSYM _tagSTACKFRAME64}
  STACKFRAME64 = _tagSTACKFRAME64;
  {$EXTERNALSYM STACKFRAME64}
  TStackFrame64 = STACKFRAME64;
  PStackFrame64 = LPSTACKFRAME64;

  // Types of Other Routines
  PREAD_PROCESS_MEMORY_ROUTINE64 = function (hProcess: THandle; qwBaseAddress: DWORD64;
    lpBuffer: PVOID; nSize: DWORD; var lpNumberOfBytesRead: DWORD): BOOL; stdcall;

  PFUNCTION_TABLE_ACCESS_ROUTINE64 = function (hProcess: THandle;
    AddrBase: DWORD64): PVOID; stdcall;

  PGET_MODULE_BASE_ROUTINE64 = function (hProcess: THandle;
    Address: DWORD64): DWORD64; stdcall;

  PTRANSLATE_ADDRESS_ROUTINE64 = function (hProcess: THandle; hThread: THandle;
    const lpaddr: ADDRESS64): DWORD64; stdcall;

  TStackWalk64 = function(MachineType: DWORD; hProcess, hThread: THandle;
    StackFrame: PStackFrame64; ContextRecord: Pointer;
    ReadMemoryRoutine: PREAD_PROCESS_MEMORY_ROUTINE64;
    FunctionTableAccessRoutine: PFUNCTION_TABLE_ACCESS_ROUTINE64;
    GetModuleBaseRoutine: PGET_MODULE_BASE_ROUTINE64;
    TranslateAddress: PTRANSLATE_ADDRESS_ROUTINE64): BOOL; stdcall;

function SymFunctionTableAccess64(hProcess: THandle; AddrBase: DWORD64): PVOID; stdcall;
  external ImagehlpLib name 'SymFunctionTableAccess64';
function SymGetModuleBase64(hProcess: THandle; Address: DWORD64): DWORD64; stdcall;
  external ImagehlpLib name 'SymGetModuleBase64';

{$ENDIF}

type
  _IMAGE_IMPORT_DESCRIPTOR = record
    case Byte of
      0: (Characteristics: DWORD);          // 0 for terminating null import descriptor
      1: (OriginalFirstThunk: DWORD;        // RVA to original unbound IAT (PIMAGE_THUNK_DATA)
          TimeDateStamp: DWORD;             // 0 if not bound,
                                            // -1 if bound, and real date\time stamp
                                            //     in IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT (new BIND)
                                            // O.W. date/time stamp of DLL bound to (Old BIND)

          ForwarderChain: DWORD;            // -1 if no forwarders
          Name: DWORD;
          FirstThunk: DWORD);                // RVA to IAT (if bound this IAT has actual addresses)
  end;
  {$EXTERNALSYM _IMAGE_IMPORT_DESCRIPTOR}
  IMAGE_IMPORT_DESCRIPTOR = _IMAGE_IMPORT_DESCRIPTOR;
  {$EXTERNALSYM IMAGE_IMPORT_DESCRIPTOR}
  TImageImportDescriptor = _IMAGE_IMPORT_DESCRIPTOR;
  PIMAGE_IMPORT_DESCRIPTOR = ^_IMAGE_IMPORT_DESCRIPTOR;
  {$EXTERNALSYM PIMAGE_IMPORT_DESCRIPTOR}
  PImageImportDescriptor = ^_IMAGE_IMPORT_DESCRIPTOR;

  _IMAGE_IMPORT_BY_NAME = record
    Hint: Word;
    Name: array[0..0] of Byte;
  end;
  {$EXTERNALSYM _IMAGE_IMPORT_BY_NAME}
  IMAGE_IMPORT_BY_NAME = _IMAGE_IMPORT_BY_NAME;
  {$EXTERNALSYM IMAGE_IMPORT_BY_NAME}
  TImageImportByName = _IMAGE_IMPORT_BY_NAME;
  PIMAGE_IMPORT_BY_NAME = ^_IMAGE_IMPORT_BY_NAME;
  {$EXTERNALSYM PIMAGE_IMPORT_BY_NAME}
  PImageImportByName = ^_IMAGE_IMPORT_BY_NAME;

  _IMAGE_THUNK_DATA32 = record
    case Byte of
      0: (ForwarderString: DWORD); // PBYTE
      1: (_Function: DWORD);       // PDWORD Function -> _Function
      2: (Ordinal: DWORD);
      3: (AddressOfData: DWORD);   // PIMAGE_IMPORT_BY_NAME
  end;
  {$EXTERNALSYM _IMAGE_THUNK_DATA32}
  IMAGE_THUNK_DATA32 = _IMAGE_THUNK_DATA32;
  {$EXTERNALSYM IMAGE_THUNK_DATA32}
  TImageThunkData32 = _IMAGE_THUNK_DATA32;
  PIMAGE_THUNK_DATA32 = ^_IMAGE_THUNK_DATA32;
  {$EXTERNALSYM PIMAGE_THUNK_DATA32}
  PImageThunkData32 = ^_IMAGE_THUNK_DATA32;

{$IFDEF WIN64}

  _IMAGE_THUNK_DATA64 = record
    case Byte of
      0: (ForwarderString: ULONGLONG); // PBYTE
      1: (_Function: ULONGLONG);       // PDWORD Function -> _Function
      2: (Ordinal: ULONGLONG);
      3: (AddressOfData: ULONGLONG);   // PIMAGE_IMPORT_BY_NAME
  end;
  {$EXTERNALSYM _IMAGE_THUNK_DATA64}
  IMAGE_THUNK_DATA64 = _IMAGE_THUNK_DATA64;
  {$EXTERNALSYM IMAGE_THUNK_DATA64}
  TImageThunkData64 = _IMAGE_THUNK_DATA64;
  PIMAGE_THUNK_DATA64 = ^_IMAGE_THUNK_DATA64;
  {$EXTERNALSYM PIMAGE_THUNK_DATA64}
  PImageThunkData64 = ^_IMAGE_THUNK_DATA64;

{$ENDIF}

type
{$IFDEF WIN64}
  PImageThunkData = PImageThunkData64;
{$ELSE}
  PImageThunkData = PImageThunkData32;
{$ENDIF}

var
  // XP 以前的平台不支持这批 API，需要动态加载
  RtlCaptureStackBackTrace: TRtlCaptureStackBackTrace = nil;
  RtlCaptureContext: TRtlCaptureContext = nil;

{$IFDEF WIN64} // 64 位下必须用未声明的 StackWalk64
  StackWalk64: TStackWalk64 = nil;
{$ENDIF}

// 查询某虚拟地址所属的分配模块 Handle，也就是 AllocationBase
function ModuleFromAddr(const Addr: Pointer): HMODULE;
var
  MI: TMemoryBasicInformation;
begin
  VirtualQuery(Addr, MI, SizeOf(MI));
  if MI.State <> MEM_COMMIT then
    Result := 0
  else
    Result := HMODULE(MI.AllocationBase);
end;

{ TCnStackInfoList }

constructor TCnStackInfoList.Create(OnlyDelphi: Boolean);
begin
  inherited Create(True);
  FModuleList := TCnModuleInfoList.Create(OnlyDelphi);
  TraceStackFrames;
end;

destructor TCnStackInfoList.Destroy;
begin
  FModuleList.Free;
  inherited;
end;

function TCnStackInfoList.GetItems(Index: Integer): TCnStackInfo;
begin
  Result := TCnStackInfo(inherited Items[Index]);
end;

procedure TCnStackInfoList.TraceStackFrames;
var
  Ctx: TContext;     // Ctx 貌似得声明靠上，不能放 Callers 这个大数组后面，否则虚拟机会出莫名其妙的错
  Info: TCnStackInfo;
  C: Word;
  I: Integer;
  Callers: array[0..MAX_STACK_COUNT - 1] of Pointer;
{$IFDEF WIN64}
  STKF64: TStackFrame64;
{$ELSE}
  STKF: TStackFrame;
{$ENDIF}
  P, T: THandle;
  Res: Boolean;
begin
  Capacity := 32;
  if Assigned(RtlCaptureStackBackTrace) then // XP/2003 or above, Support 32/64
  begin
    C := RtlCaptureStackBackTrace(0, MAX_STACK_COUNT, Callers[0], nil);
    for I := 0 to C - 1 do
    begin
      Info := TCnStackInfo.Create;
      Info.CallerAddr := Callers[I];
      Add(Info);
    end;
  end
  else if Assigned(RtlCaptureContext) {$IFDEF WIN64} and Assigned(StackWalk64) {$ENDIF} then
  begin
    // Using StackWalk in ImageHlp and RtlCaptureContext
    FillChar(Ctx, SizeOf(TContext), 0);
    RtlCaptureContext(@Ctx);                   // 64位的情况下，居然虚拟机上可能会出错
{$IFDEF WIN64}
    FillChar(STKF64, SizeOf(TStackFrame64), 0);

    STKF64.AddrPC.Mode         := AddrModeFlat;
    STKF64.AddrStack.Mode      := AddrModeFlat;
    STKF64.AddrFrame.Mode      := AddrModeFlat;
    STKF64.AddrPC.Offset       := Ctx.Rip;
    STKF64.AddrStack.Offset    := Ctx.Rsp;
    STKF64.AddrFrame.Offset    := Ctx.Rbp;
{$ELSE}
    FillChar(STKF, SizeOf(TStackFrame), 0);

    STKF.AddrPC.Mode         := AddrModeFlat;
    STKF.AddrStack.Mode      := AddrModeFlat;
    STKF.AddrFrame.Mode      := AddrModeFlat;
    STKF.AddrPC.Offset       := Ctx.Eip;
    STKF.AddrStack.Offset    := Ctx.Esp;
    STKF.AddrFrame.Offset    := Ctx.Ebp;
{$ENDIF}

    P := GetCurrentProcess;
    T := GetCurrentThread;

    while True do
    begin
{$IFDEF WIN64}
      // FIXME: 64位下 StackWalk64 始终抓不到堆栈，咋办？
      Res := StackWalk64(IMAGE_FILE_MACHINE_AMD64, P, T, @STKF64, @Ctx, nil, @SymFunctionTableAccess64,
        @SymGetModuleBase64, nil);

      if Res and (STKF64.AddrPC.Offset <> 0) then
      begin
        if STKF64.AddrReturn.Offset = 0 then
          Break;

        Info := TCnStackInfo.Create;
        Info.CallerAddr := Pointer(STKF64.AddrPC.Offset);
        Add(Info);
      end
      else
        Break;

      if STKF64.AddrReturn.Offset = 0 then
        Break;
{$ELSE}
      Res := StackWalk(IMAGE_FILE_MACHINE_I386, P, T, @STKF, @Ctx, nil, @SymFunctionTableAccess,
        @SymGetModuleBase, nil);

      if Res and (STKF.AddrPC.Offset <> 0) then
      begin
        if STKF.AddrReturn.Offset = 0 then
          Break;

        Info := TCnStackInfo.Create;
        Info.CallerAddr := Pointer(STKF.AddrPC.Offset);
        Add(Info);
      end
      else
        Break;

      if STKF.AddrReturn.Offset = 0 then
        Break;
{$ENDIF}
    end;
  end;
end;

procedure TCnStackInfoList.DumpToStrings(List: TStrings);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    List.Add(Format(STACK_INFO_FMT, [TCnNativeUInt(Items[I].CallerAddr)]));
end;

{ TCnModuleInfoList }

function TCnModuleInfoList.AddModule(PH: THandle; MH: HMODULE): TCnModuleInfo;
var
  ModuleInfo: TModuleInfo;
  Info: TCnModuleInfo;
  Res: DWORD;
  AName: array[0..MAX_PATH - 1] of Char;
begin
  Result := nil;

  // 根据每个 Module Handle 拿 Module 基地址等信息
  if GetModuleInformation(PH, MH, @ModuleInfo, SizeOf(TModuleInfo)) then
  begin
    Info := TCnModuleInfo.Create;
    Info.HModule := MH;
    Info.StartAddr := ModuleInfo.lpBaseOfDll;
    Info.Size := ModuleInfo.SizeOfImage;
    Info.EndAddr := Pointer(TCnNativeUInt(ModuleInfo.lpBaseOfDll) + ModuleInfo.SizeOfImage);

    Res := GetModuleBaseName(PH, MH, @AName[0], SizeOf(AName));
    if Res > 0 then
    begin
      SetLength(Info.FBaseName, Res);
      System.Move(AName[0], Info.FBaseName[1], Res * SizeOf(Char));
    end;
    Res := GetModuleFileName(MH, @AName[0], SizeOf(AName));
    if Res > 0 then
    begin
      SetLength(Info.FFullName, Res);
      System.Move(AName[0], Info.FFullName[1], Res * SizeOf(Char));
    end;
    Add(Info);
    Result := Info;
  end;
end;

procedure TCnModuleInfoList.BuildModulesList;
var
  ProcessHandle: THandle;
  Needed: DWORD;
  Modules: array of THandle;
  I, Cnt: Integer;
  Res: Boolean;
  MemInfo: TMemoryBasicInformation;
  Base: PByte;
  LastAllocBase: Pointer;
  QueryRes: DWORD;
  CurModule: PLibModule;
begin
  if FDelphiOnly then
  begin
    CurModule := LibModuleList;
    while CurModule <> nil do
    begin
      CreateItemForAddress(Pointer(CurModule.Instance), True);
      CurModule := CurModule.Next;
    end;
  end
  else
  begin
    ProcessHandle := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, GetCurrentProcessId);
    if ProcessHandle <> 0 then
    begin
      try
        Res := EnumProcessModules(ProcessHandle, nil, 0, Needed);
        if Res then
        begin
          Cnt := Needed div SizeOf(HMODULE);
          SetLength(Modules, Cnt);
          if EnumProcessModules(ProcessHandle, @Modules[0], Needed, Needed) then
          begin
            for I := 0 to Cnt - 1 do
              CheckDelphiModule(AddModule(ProcessHandle, Modules[I]));
          end;
        end
        else
        begin
          Base := nil;
          LastAllocBase := nil;
          FillChar(MemInfo, SizeOf(TMemoryBasicInformation), #0);

          QueryRes := VirtualQueryEx(ProcessHandle, Base, MemInfo, SizeOf(TMemoryBasicInformation));
          while QueryRes = SizeOf(TMemoryBasicInformation) do
          begin
            if MemInfo.AllocationBase <> LastAllocBase then
            begin
              if MemInfo.Type_9 = MEM_IMAGE then
                CheckDelphiModule(AddModule(ProcessHandle, HMODULE(MemInfo.AllocationBase)));
              LastAllocBase := MemInfo.AllocationBase;
            end;
            Inc(Base, MemInfo.RegionSize);
            QueryRes := VirtualQueryEx(ProcessHandle, Base, MemInfo, SizeOf(TMemoryBasicInformation));
          end;
        end;
      finally
        CloseHandle(ProcessHandle);
      end;
    end;
  end;
end;

// 在 System 的系统模块链里查询 Delphi 模块
procedure TCnModuleInfoList.CheckDelphiModule(Info: TCnModuleInfo);
var
  CurModule: PLibModule;
begin
  if (Info <> nil) and (Info.HModule <> 0) then
  begin
    CurModule := LibModuleList;
    while CurModule <> nil do
    begin
      if CurModule.Instance = Info.HModule then
      begin
        Info.IsDelphi := True;
        Exit;
      end;
      CurModule := CurModule.Next;
    end;
  end;
end;

constructor TCnModuleInfoList.Create;
begin
  inherited Create(True);
  FDelphiOnly := ADelphiOnly;
  BuildModulesList;
end;

function TCnModuleInfoList.CreateItemForAddress(Addr: Pointer;
  AIsDelphi: Boolean): TCnModuleInfo;
var
  Module: HMODULE;
  ProcessHandle: THandle;
begin
  Result := nil;
  Module := ModuleFromAddr(Addr);
  if Module > 0 then
  begin
    ProcessHandle := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, GetCurrentProcessId);
    if ProcessHandle <> 0 then
    begin
      try
        Result := AddModule(ProcessHandle, Module);
        if Result <> nil then
          Result.IsDelphi := AIsDelphi;
      finally
        CloseHandle(ProcessHandle);
      end;
    end;
  end;
end;

destructor TCnModuleInfoList.Destroy;
begin

  inherited;
end;

procedure TCnModuleInfoList.DumpToStrings(List: TStrings);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    List.Add(Items[I].ToString);
end;

function TCnModuleInfoList.GetItems(Index: Integer): TCnModuleInfo;
begin
  Result := TCnModuleInfo(inherited Items[Index]);
end;

function TCnModuleInfoList.GetModuleFromAddress(Addr: Pointer): TCnModuleInfo;
var
  I: Integer;
  Item: TCnModuleInfo;
begin
  Result := nil;
  for I := 0 to Count - 1 do
  begin
    Item := Items[I];
    if (TCnNativeUInt(Item.StartAddr) <= TCnNativeUInt(Addr)) and
      (TCnNativeUInt(Item.EndAddr) > TCnNativeUInt(Addr)) then
    begin
      Result := Item;
      Exit;
    end;
  end;
end;

function TCnModuleInfoList.IsDelphiModuleAddress(Addr: Pointer): Boolean;
var
  Info: TCnModuleInfo;
begin
  Info := GetModuleFromAddress(Addr);
  Result := (Info <> nil) and Info.IsDelphi;
end;

function TCnModuleInfoList.IsValidModuleAddress(Addr: Pointer): Boolean;
begin
  Result := GetModuleFromAddress(Addr) <> nil;
end;

{ TCnModuleInfo }

function TCnModuleInfo.ToString: string;
begin
  Result := Format(MODULE_INFO_FMT, [FHModule, TCnNativeUInt(FStartAddr),
    TCnNativeUInt(FEndAddr), FSize, Integer(FIsDelphi), FBaseName, FFullName]);
end;

procedure InitAPIs;
var
  H: HINST;
  P: Pointer;
begin
  H := GetModuleHandle(kernel32);
  if H <> 0 then
  begin
    P := GetProcAddress(H, 'RtlCaptureStackBackTrace');
    if P <> nil then
      RtlCaptureStackBackTrace := TRtlCaptureStackBackTrace(P);
  end;
  H := GetModuleHandle('ntdll.dll');
  if H <> 0 then
  begin
    P := GetProcAddress(H, 'RtlCaptureContext');
    if P <> nil then
      RtlCaptureContext := TRtlCaptureContext(P);
  end;
{$IFDEF WIN64}
  H := GetModuleHandle(ImagehlpLib);
  if H <> 0 then
  begin
    P := GetProcAddress(H, 'StackWalk64');
    if P <> nil then
      StackWalk64 := TStackWalk64(P);
  end;
{$ENDIF}
end;

// ===================== 进程内用改写 IAT 表的方式 Hook API ====================

// Hook 为 True 时进行 Hook 动作，要求传入新地址。旧地址通过 OldAddress 传出去
// Hook 为 False 时进行 UnHook 动作，要求传入旧地址。
function HookImportAddressTable(Hook: Boolean; const ModuleName, FuncName: string;
  var OldAddress: Pointer; NewAddress: Pointer; ModuleHandle: THandle): Boolean;
var
  HP, HM: THandle;
  Size: DWORD;
  MN, FN: PAnsiChar;
  PIP: PImageImportDescriptor;
  PIIBN: PImageImportByName;
  PITO, PITR: PImageThunkData;
  AMN, AFN: AnsiString;
  MBI: TMemoryBasicInformation;
  FindingAddress: Pointer;
begin
  Result := False;
  if (ModuleName = '') or (FuncName = '') then
    Exit;

  if Hook and (NewAddress = nil) then
    Exit;

  if not Hook and (OldAddress = nil) then
    Exit;

  HP := ModuleHandle;           // 获得要实施 Hook 的模块
  if HP = 0 then
    HP := GetModuleHandle(nil); // 获得 EXE 的模块 Handle
  if HP = 0 then
    Exit;

  Size := 0;
  PIP := PImageImportDescriptor(ImageDirectoryEntryToData(Pointer(HP), True,
    IMAGE_DIRECTORY_ENTRY_IMPORT, Size));

  if PIP = nil then
    Exit;

  AMN := AnsiString(LowerCase(ModuleName));
  while PIP^.Name <> 0 do
  begin
    MN := PAnsiChar(TCnNativeUInt(HP) + PIP^.Name);
    if MN = '' then
      Break;

    if AnsiStrIComp(MN, PAnsiChar(AMN)) = 0 then
    begin
      PITR := PImageThunkData(TCnNativeUInt(HP) + PIP^.FirstThunk);

      // 找到了输入的 DLL，分两种情况处理
      if PIP^.OriginalFirstThunk <> 0 then // 有 OFT，表示可以根据名字找 IAT 里的东西
      begin
        PITO := PImageThunkData(TCnNativeUInt(HP) + PIP^.OriginalFirstThunk);
        AFN := AnsiString(FuncName);

        while PITO^._Function <> 0 do
        begin
          if (PITO^.Ordinal and IMAGE_ORDINAL_FLAG) <> IMAGE_ORDINAL_FLAG then
          begin
            PIIBN := PImageImportByName(TCnNativeUInt(HP) + PITO^.AddressOfData);
            FN := PAnsiChar(@(PIIBN^.Name[0]));

            if (FN <> '') and (AnsiStrIComp(FN, PAnsiChar(AFN)) = 0) then
            begin
              // 找到了要替换的函数地址，改权限先
              VirtualQuery(PITR, MBI, SizeOf(TMemoryBasicInformation));
              VirtualProtect(MBI.BaseAddress, MBI.RegionSize, PAGE_READWRITE, @MBI.Protect);

              if Hook then
              begin
                // 替换
                OldAddress := Pointer(PITR^._Function);
                PITR^._Function := TCnNativeUInt(NewAddress);
              end
              else
              begin
                // 恢复
                PITR^._Function := TCnNativeUInt(OldAddress);
              end;

              Result := True;
              Exit;
            end;
          end;

          Inc(PITO);
          Inc(PITR);
        end;
      end
      else // OFT 为 0，表示要自行搜索 FirstTrunk 指向的 IAT，可能有多个
      begin
        HM := GetModuleHandle(PChar(ModuleName));
        if HM <> 0 then
        begin
          FindingAddress := GetProcAddress(HM, PChar(FuncName));

          if Hook then
          begin
            while PITR^._Function <> 0 do
            begin
              if PITR^._Function = TCnNativeUInt(FindingAddress) then
              begin
                // 替换
                VirtualQuery(PITR, MBI, SizeOf(TMemoryBasicInformation));
                VirtualProtect(MBI.BaseAddress, MBI.RegionSize, PAGE_READWRITE, @MBI.Protect);

                OldAddress := Pointer(PITR^._Function);
                PITR^._Function := TCnNativeUInt(NewAddress);
                Result := True;
              end;
              Inc(PITR);
            end;
          end
          else // 循环查找恢复，可能有多个
          begin
            while PITR^._Function <> 0 do
            begin
              if PITR^._Function = TCnNativeUInt(NewAddress) then
              begin
                VirtualQuery(PITR, MBI, SizeOf(TMemoryBasicInformation));
                VirtualProtect(MBI.BaseAddress, MBI.RegionSize, PAGE_READWRITE, @MBI.Protect);

                if OldAddress <> nil then // 恢复时优先以传入的地址为准
                  PITR^._Function := TCnNativeUInt(OldAddress)
                else
                  PITR^._Function := TCnNativeUInt(FindingAddress);

                Result := True;
              end;
              Inc(PITR);
            end;
          end;
        end;
      end;
    end;
    Inc(PIP);
  end;
end;

function CnHookImportAddressTable(const ImportModuleName, ImportFuncName: string;
  out OldAddress: Pointer; NewAddress: Pointer; ModuleHandle: THandle): Boolean;
begin
  Result := HookImportAddressTable(True, ImportModuleName, ImportFuncName,
    OldAddress, NewAddress, ModuleHandle);
end;

function CnUnHookImportAddressTable(const ImportModuleName, ImportFuncName: string;
  OldAddress, NewAddress: Pointer; ModuleHandle: THandle): Boolean;
begin
  Result := HookImportAddressTable(False, ImportModuleName, ImportFuncName,
    OldAddress, NewAddress, ModuleHandle);
end;

initialization
  InitAPIs;

end.





