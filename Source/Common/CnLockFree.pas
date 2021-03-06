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

unit CnLockFree;
{* |<PRE>
================================================================================
* 软件名称：CnPack 组件包
* 单元名称：涉及到无锁机制的一些原子操作封装以及无锁数据结构的实现
* 单元作者：刘啸 (liuxiao@cnpack.org)
* 备    注：封装了 CnAtomicCompareAndSet 的 CAS 实现，适应 32 位和 64 位
*           并基于此实现了自旋锁
* 开发平台：PWin2000 + Delphi 5.0
* 兼容测试：PWin9X/2000/XP + Delphi 5/ 10.3，包括 Win32/64
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 修改记录：2021.01.10 V1.0
*               创建单元，实现功能
================================================================================
|</PRE>}

interface

{$I CnPack.inc}

uses
  SysUtils, {$IFDEF MSWINDOWS} Windows, {$ENDIF} Classes;

type
{$IFDEF WIN64}
  TCnSpinLockRecord = NativeInt;
{$ELSE}
  TCnSpinLockRecord = Integer;
{$ENDIF}
  {* 自旋锁，值为 1 时表示有别人锁了它，0 表示空闲}

  PCnLockFreeLinkedNode = ^TCnLockFreeLinkedNode;

  TCnLockFreeLinkedNode = packed record
  {* 无锁单链表节点}
    Key: TObject;
    Value: TObject;
    Next: PCnLockFreeLinkedNode;
  end;

  TCnLockFreeLinkedList = class
  {* 无锁单链表实现}
  private
    FHead: PCnLockFreeLinkedNode; // 固定的头节点指针
    FNode: TCnLockFreeLinkedNode; // 隐藏的头节点，不参与统计、搜索、删除等
    function GetTailNode: PCnLockFreeLinkedNode;
  protected
    function CreateNode: PCnLockFreeLinkedNode;
    procedure FreeNode(Node: PCnLockFreeLinkedNode);
  public
    constructor Create;
    destructor Destroy; override;

    function GetCount: Integer;
    {* 遍历获取有多少个节点，不包括隐藏节点}
    procedure Clear;
    {* 全部清空}
    procedure Append(Key, Value: TObject);
    {* 在链表尾部直接添加新节点，调用者需自行保证 Key 不存在于链表中否则搜索会出错}
    procedure Add(Key, Value: TObject);
    {* 在链表中根据 Key 查找节点并替换，如不存在则在尾部添加新节点}
    function Remove(Key: TObject): Boolean;
    {* （还未实现）在链表中根据 Key 查找节点并删除，返回是否删除成功}
    function HasKey(Key: TObject): Boolean;
    {* 在链表中搜索指定 Key 是否存在}
  end;

//------------------------------------------------------------------------------
// 原子操作封装
//------------------------------------------------------------------------------

function CnAtomicIncrement32(var Addend: Integer): Integer;
{* 原子操作令一 32 位值增 1}

function CnAtomicDecrement32(var Addend: Integer): Integer;
{* 原子操作令一 32 位值减 1}

function CnAtomicExchange32(var Target: Integer; Value: Integer): Integer;
{* 原子操作令俩 32 位值交换}

function CnAtomicExchangeAdd32(var Addend: LongInt; Value: LongInt): Longint;
{* 原子操作令 32 位值 Addend := Addend + Value，返回 Addend 原始值}

function CnAtomicCompareExchange(var Target: Pointer; NewValue: Pointer; Comperand: Pointer): Pointer;
{* 原子操作比较 Target 与 Comperand 俩值，相等时则将 NewValue 赋值给 Target，返回旧的 Target 值
  32 位下支持 32 位值，64 位下支持 64 位值}

function CnAtomicCompareAndSet(var Target: Pointer; NewValue: Pointer; Comperand: Pointer): Boolean;
{* 原子操作执行以下代码，比较 Target 与 Comperand 俩值，相等时则将 NewValue 赋值给 Target，
  32 位下支持 32 位值，64 位下支持 64 位值，未发生赋值操作时返回 False，赋值时返回 True
  注意 NewValue 不要等于 Target，否则无法区分是否执行了赋值操作，因为无论是否赋值都一样
  if Comperand = Target then
  begin
    Target := NewValue;
    Result := True;
  end
  else
    Result := False;
}

//------------------------------------------------------------------------------
// 自旋锁
//------------------------------------------------------------------------------

procedure CnInitSpinLockRecord(var Critical: TCnSpinLockRecord);
{* 初始化一个自旋锁，其实就是赋值为 0，无需释放}

procedure CnSpinLockEnter(var Critical: TCnSpinLockRecord);
{* 进入自旋锁}

procedure CnSpinLockLeave(var Critical: TCnSpinLockRecord);
{* 离开自旋锁}

implementation

function CnAtomicIncrement32(var Addend: Integer): Integer;
begin
{$IFDEF SUPPORT_ATOMIC}
  AtomicIncrement(Addend);
{$ELSE}
  Result := InterlockedIncrement(Addend);
{$ENDIF}
end;

function CnAtomicDecrement32(var Addend: Integer): Integer;
begin
{$IFDEF SUPPORT_ATOMIC}
  AtomicDecrement(Addend);
{$ELSE}
  Result := InterlockedDecrement(Addend);
{$ENDIF}
end;

function CnAtomicExchange32(var Target: Integer; Value: Integer): Integer;
begin
{$IFDEF SUPPORT_ATOMIC}
  AtomicExchange(Target, Value);
{$ELSE}
  Result := InterlockedExchange(Target, Value);
{$ENDIF}
end;

function CnAtomicExchangeAdd32(var Addend: LongInt; Value: LongInt): LongInt;
begin
{$IFDEF WIN64}
  Result := InterlockedExchangeAdd(Addend, Value);
{$ELSE}
  Result := InterlockedExchangeAdd(@Addend, Value);
{$ENDIF}
end;

function CnAtomicCompareExchange(var Target: Pointer; NewValue: Pointer; Comperand: Pointer): Pointer;
begin
{$IFDEF SUPPORT_ATOMIC}
  Result := AtomicCmpExchange(Target, NewValue, Comperand);
{$ELSE}
  Result := InterlockedCompareExchange(Target, NewValue, Comperand);
{$ENDIF}
end;

{$IFDEF SUPPORT_ATOMIC}

function CnAtomicCompareAndSet(var Target: Pointer; NewValue: Pointer;
  Comperand: Pointer): Boolean;
begin
  AtomicCmpExchange(Target, NewValue, Comperand, Result);
end;

{$ELSE}

{$IFDEF WIN64}

// XE2 的 Win64 下没有 Atomic 系列函数
function CnAtomicCompareAndSet(var Target: Pointer; NewValue: Pointer;
  Comperand: Pointer): Boolean; assembler;
asm
  // API 里的 InterlockedCompareExchange 不会返回是否成功，不得不用汇编代替
  MOV  RAX,  R8
  LOCK CMPXCHG [RCX], RDX
  SETZ AL
  AND RAX, $FF
end;

{$ELSE}

// XE2 或以下版本的 Win32 实现
function CnAtomicCompareAndSet(var Target: Pointer; NewValue: Pointer;
  Comperand: Pointer): Boolean; assembler;
asm
  // API 里的 InterlockedCompareExchange 不会返回是否成功，不得不用汇编代替
  // 其中 @Target 是 EAX, NewValue 是 EDX，Comperand 是 ECX，
  // 要做一次 ECX 与 EAX 的互换才能调用 LOCK CMPXCHG [ECX], EDX，结果返回在 AL 中
  XCHG  EAX, ECX
  LOCK CMPXCHG [ECX], EDX
  SETZ AL
  AND EAX, $FF
end;

{$ENDIF}

{$ENDIF}

procedure CnInitSpinLockRecord(var Critical: TCnSpinLockRecord);
begin
  Critical := 0;
end;

procedure CnSpinLockEnter(var Critical: TCnSpinLockRecord);
begin
  repeat
    while Critical <> 0 do
      ;  // 此处如果改成 Sleep(0) 就会有线程切换开销，就不是自旋锁了
  until CnAtomicCompareAndSet(Pointer(Critical), Pointer(1), Pointer(0));
end;

procedure CnSpinLockLeave(var Critical: TCnSpinLockRecord);
begin
  while not CnAtomicCompareAndSet(Pointer(Critical), Pointer(0), Pointer(1)) do
    Sleep(0);
end;

{ TCnLockFreeLinkedList }

procedure TCnLockFreeLinkedList.Add(Key, Value: TObject);
var
  P: PCnLockFreeLinkedNode;
begin
  P := FHead.Next;
  while P <> nil do
  begin
    if P^.Key = Key then
    begin
      P^.Value := Value;
      Exit;
    end;
    P := P^.Next;
  end;

  // 没找到 Key，添加
  Append(Key, Value);
end;

procedure TCnLockFreeLinkedList.Append(Key, Value: TObject);
var
  Node, P: PCnLockFreeLinkedNode;
begin
  Node := CreateNode;
  Node^.Key := Key;
  Node^.Value := Value;

  // 原子操作，先摸到尾巴 Tail，判断 Tail 的 Next 是否是 nil，是则将 Tail 的 Next 设为 NewNode
  // 如果其他线程修改了 Tail，导致这里取到的 Tail 不是尾巴，那么 Tail 的 Next 就不为 nil，就得重试
  repeat
    P := GetTailNode;
  until CnAtomicCompareAndSet(Pointer(P^.Next), Pointer(Node), nil);
end;

procedure TCnLockFreeLinkedList.Clear;
var
  P, N: PCnLockFreeLinkedNode;
begin
  P := FHead.Next;
  while P <> nil do
  begin
    N := P;
    P := P^.Next;
    FreeNode(N);
  end;
  FHead := @FNode;
end;

constructor TCnLockFreeLinkedList.Create;
begin
  inherited;
  FNode.Key := nil;
  FNode.Value := nil;
  FNode.Next := nil;

  FHead := @FNode;
end;

function TCnLockFreeLinkedList.CreateNode: PCnLockFreeLinkedNode;
begin
  New(Result);
  Result^.Next := nil;
end;

destructor TCnLockFreeLinkedList.Destroy;
begin
  Clear;
  inherited;
end;

procedure TCnLockFreeLinkedList.FreeNode(Node: PCnLockFreeLinkedNode);
begin
  Dispose(Node);
end;

function TCnLockFreeLinkedList.GetCount: Integer;
var
  P: PCnLockFreeLinkedNode;
begin
  Result := 0;
  P := FHead.Next;
  while P <> nil do
  begin
    Inc(Result);
    P := P^.Next;
  end;
end;

function TCnLockFreeLinkedList.GetTailNode: PCnLockFreeLinkedNode;
begin
  Result := FHead;
  while Result^.Next <> nil do
    Result := Result^.Next;
end;

function TCnLockFreeLinkedList.HasKey(Key: TObject): Boolean;
var
  P: PCnLockFreeLinkedNode;
begin
  Result := False;
  P := FHead.Next;
  while P <> nil do
  begin
    if P^.Key = Key then
    begin
      Result := True;
      Exit;
    end;
    P := P^.Next;
  end;
end;

function TCnLockFreeLinkedList.Remove(Key: TObject): Boolean;
begin
  // TODO: 这个比较难实现
  raise Exception.Create('NOT Implemented');
end;

end.
