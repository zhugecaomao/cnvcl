unit UnitLockFree;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, SyncObjs;

type
  TFormLockFree = class(TForm)
    btnTestNoCritical: TButton;
    btnTestCritical: TButton;
    btnTestSysCritical: TButton;
    btnTestLockFreeLinkedList: TButton;
    procedure btnTestNoCriticalClick(Sender: TObject);
    procedure btnTestCriticalClick(Sender: TObject);
    procedure btnTestSysCriticalClick(Sender: TObject);
    procedure btnTestLockFreeLinkedListClick(Sender: TObject);
  private
    procedure NoCriticalTerminate(Sender: TObject);
    procedure CriticalTerminate(Sender: TObject);
    procedure SysCriticalTerminate(Sender: TObject);
    procedure LinkedListTerminate(Sender: TObject);
  public
    { Public declarations }
  end;

var
  FormLockFree: TFormLockFree;

implementation

uses
  CnLockFree;

{$R *.DFM}

type
  TNoCriticalThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TCriticalThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TSysCriticalThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TLinkedListThread = class(TThread)
  private
    FBase: Integer;
  protected
    procedure Execute; override;
  public
    property Base: Integer read FBase write FBase;
  end;

var
  NoCriticalValue: Integer;
  NoCriticalTerminateCount: Integer;

  CS: TCriticalSection;

  CO: TCnSpinLockRecord;
  CriticalValue: Integer;
  CriticalTerminateCount: Integer;

  FLink: TCnLockFreeLinkedList;
  LinkTerminateCount: Integer;

procedure TFormLockFree.btnTestNoCriticalClick(Sender: TObject);
var
  T1, T2, T3: TNoCriticalThread;
begin
  NoCriticalValue := 0;
  NoCriticalTerminateCount := 0;

  T1 := TNoCriticalThread.Create(True);
  T2 := TNoCriticalThread.Create(True);
  T3 := TNoCriticalThread.Create(True);
  T1.FreeOnTerminate := True;
  T2.FreeOnTerminate := True;
  T3.FreeOnTerminate := True;
  T1.OnTerminate := NoCriticalTerminate;
  T2.OnTerminate := NoCriticalTerminate;
  T3.OnTerminate := NoCriticalTerminate;
  T1.Resume;
  T2.Resume;
  T3.Resume;
end;

{ TNoCriticalThread }

procedure TNoCriticalThread.Execute;
var
  I, Old: Integer;
begin
  for I := 1 to 1000 do
  begin
    Old := NoCriticalValue;
    Sleep(0);
    NoCriticalValue := Old + 1;
  end;
end;

procedure TFormLockFree.NoCriticalTerminate(Sender: TObject);
begin
  NoCriticalTerminateCount := NoCriticalTerminateCount + 1;

  if NoCriticalTerminateCount >= 3 then
    ShowMessage(IntToStr(NoCriticalValue) + ' Terminated: ' + IntToStr(NoCriticalTerminateCount));
end;

{ TCriticalThread }

procedure TCriticalThread.Execute;
var
  I, Old: Integer;
begin
  for I := 1 to 10000 do
  begin
    CnSpinLockEnter(CO);
    Old := CriticalValue;
    Sleep(0);
    CriticalValue := Old + 1;
    CnSpinLockLeave(CO);
  end;
end;

procedure TFormLockFree.btnTestCriticalClick(Sender: TObject);
var
  T1, T2, T3: TCriticalThread;
begin
  CriticalValue := 0;
  CriticalTerminateCount := 0;
  CnInitSpinLockRecord(CO);

  T1 := TCriticalThread.Create(True);
  T2 := TCriticalThread.Create(True);
  T3 := TCriticalThread.Create(True);
  T1.FreeOnTerminate := True;
  T2.FreeOnTerminate := True;
  T3.FreeOnTerminate := True;
  T1.OnTerminate := CriticalTerminate;
  T2.OnTerminate := CriticalTerminate;
  T3.OnTerminate := CriticalTerminate;
  T1.Resume;
  T2.Resume;
  T3.Resume;
end;

procedure TFormLockFree.CriticalTerminate(Sender: TObject);
begin
  CriticalTerminateCount := CriticalTerminateCount + 1;

  if CriticalTerminateCount >= 3 then
    ShowMessage(IntToStr(CriticalValue) + ' Terminated: ' + IntToStr(CriticalTerminateCount));
end;

{ TSysCriticalThread }

procedure TSysCriticalThread.Execute;
var
  I, Old: Integer;
begin
  for I := 1 to 10000 do
  begin
    CS.Enter;
    Old := CriticalValue;
    Sleep(0);
    CriticalValue := Old + 1;
    CS.Leave;
  end;
end;

procedure TFormLockFree.btnTestSysCriticalClick(Sender: TObject);
var
  T1, T2, T3: TSysCriticalThread;
begin
  CriticalValue := 0;
  CriticalTerminateCount := 0;
  CS := TCriticalSection.Create;

  T1 := TSysCriticalThread.Create(True);
  T2 := TSysCriticalThread.Create(True);
  T3 := TSysCriticalThread.Create(True);
  T1.FreeOnTerminate := True;
  T2.FreeOnTerminate := True;
  T3.FreeOnTerminate := True;
  T1.OnTerminate := SysCriticalTerminate;
  T2.OnTerminate := SysCriticalTerminate;
  T3.OnTerminate := SysCriticalTerminate;
  T1.Resume;
  T2.Resume;
  T3.Resume;
end;

procedure TFormLockFree.SysCriticalTerminate(Sender: TObject);
begin
  CriticalTerminateCount := CriticalTerminateCount + 1;

  if CriticalTerminateCount >= 3 then
  begin
    ShowMessage(IntToStr(CriticalValue) + ' Terminated: ' + IntToStr(CriticalTerminateCount));
    CS.Free;
  end;
end;

procedure TFormLockFree.btnTestLockFreeLinkedListClick(Sender: TObject);
var
  T1, T2, T3: TLinkedListThread;
begin
  FLink := TCnLockFreeLinkedList.Create;
  LinkTerminateCount := 0;

  T1 := TLinkedListThread.Create(True);
  T2 := TLinkedListThread.Create(True);
  T3 := TLinkedListThread.Create(True);
  T1.Base := 0;
  T2.Base := 10000;
  T3.Base := 20000;

  T1.FreeOnTerminate := True;
  T2.FreeOnTerminate := True;
  T3.FreeOnTerminate := True;
  T1.OnTerminate := LinkedListTerminate;
  T2.OnTerminate := LinkedListTerminate;
  T3.OnTerminate := LinkedListTerminate;
  T1.Resume;
  T2.Resume;
  T3.Resume;
end;

{ TLinkedListThread }

procedure TLinkedListThread.Execute;
var
  I: Integer;
begin
  for I := 1 to 1000 do
    FLink.Append(TObject(I + FBase), nil);
end;

procedure TFormLockFree.LinkedListTerminate(Sender: TObject);
begin
  LinkTerminateCount := LinkTerminateCount + 1;

  if LinkTerminateCount >= 3 then
  begin
    ShowMessage(IntToStr(FLink.GetCount) + ' Terminated: ' + IntToStr(LinkTerminateCount));
    FLink.Free;
  end;
end;

end.
