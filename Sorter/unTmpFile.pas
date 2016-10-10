unit unTmpFile;

interface
uses System.Classes,
     System.Generics.Collections,
     System.Generics.Defaults;

type

  TTmpFile = class
  private
    stm : TBufferedFileStream;
    fLinesCount: Int64;
    fClosed: Boolean;
    fMaxDigit: Integer;
    fFileName: String;
    function getFullFileName: String;
    function getIntermediateFileName: String;
    function getSortedFileName: String;
  public
    constructor Create(const FileName : String);
    destructor  Destroy; override;
    procedure   WriteLn(const Str : String);
    procedure   Close;
    function    RenameTmpFile : String;

    property  fileName : String read fFileName;                           // file name w/o extention
    property  fullFileName : String read getFullFileName;                 // full file name with extention
    property  intermediateFileName : String read getIntermediateFileName; // intermediate file name with extention
    property  sortedFileName : String read getSortedFileName;             // sorted file name with extention
    property  linesCount: Int64 read fLinesCount;
    property  maxDigit : Integer read fMaxDigit;
  end;

  TTmpFileList = class( TObjectList<TTmpFile> )
  private
    fSorted : Boolean;
    fLock : TObject;
    fCurrent : Integer;
  public
    constructor Create(AOwnsObjects: Boolean = True); overload;
    destructor  Destroy; override;
    function    LockList : TTmpFileList;
    procedure   UnlockList;
    procedure   setFirst;
    function    getNext : TTmpFile;
    procedure   SortFileList;
    function    getTmpFile(const AFileName : String) : TTmpFile;
  end;

procedure makeTmpFileNames(List : TTmpFileList; const StartWith : String; charsCount : Integer);

implementation
uses WinAPI.Windows,
     System.SysUtils,
     System.Math,
     unCommonData;

const TMP_EXT  = '.txt';
      SORT_ADD = '.sorted'+TMP_EXT;

type
  TTmpFileComparer = class(TComparer<TTmpFile>)
  public
    function Compare(const Left, Right: TTmpFile): Integer; override;
  end;

procedure makeTmpFileNames(List : TTmpFileList; const StartWith : String; charsCount : Integer);
var i, _Depth : Integer;
    _Str : String;

begin
  _Depth := charsCount;
  _Str   := EmptyStr;
  dec(_Depth);
  if (_Depth >= 0) then
    begin
      for i:=Low(uprCaseShort) to High(uprCaseShort) do
        begin

          _Str := StartWith + uprCaseShort[i];
          if _Str.Chars[ Length(StartWith)-1 ]=' ' then Continue;

          if _Depth>0
            then makeTmpFileNames(List, _Str, _Depth)
            else begin
                   List.Add( TTmpFile.Create( _Str ) );
                   _Str := EmptyStr;
                 end;
        end;
    end;
end;

{ TTmpFile }

constructor TTmpFile.Create(const FileName: String);
begin
  inherited Create;
  fFileName   := FileName;
  stm         := TBufferedFileStream.Create(getFullFileName, fmCreate, FILE_BUFF_LEN);
  fLinesCount := 0;
  fMaxDigit   := 0;
  fClosed     := False;
end;

destructor TTmpFile.Destroy;
begin
  if Assigned(stm) then Close;
  inherited;
end;

procedure TTmpFile.Close;
begin
  stm.FlushBuffer;
  FreeAndNil( stm );
  fClosed := True;
end;


function TTmpFile.getFullFileName: String;
begin
  Result := fFileName + TMP_EXT;
end;

function TTmpFile.getSortedFileName: String;
begin
  Result := fFileName + SORT_ADD;
end;


function TTmpFile.getIntermediateFileName: String;
var SR : TSearchRec;
begin
  Result := EmptyStr;
  if System.SysUtils.FindFirst(fFileName+'*'+TMP_EXT, faAnyFile, sr) = 0 then
    begin
      Result := SR.Name;
      System.SysUtils.FindClose(SR);
    end;
end;

procedure TTmpFile.WriteLn(const Str: String);
var ar : TArray<String>;
    num, tmp : String;
begin
  if Str<>EmptyStr then
    begin
      ar  := Str.Split( ['.'] );
      num := Trim( ar[0] );
      tmp := Trim( ar[1] );
      fMaxDigit := Max(fMaxDigit, Length(num) );

      StrToStream( stm, tmp+'.'+num+sLineBreak );
      inc(fLinesCount);
    end;
end;

function TTmpFile.RenameTmpFile : String;
var newFileName : String;
begin
  Result := EmptyStr;
  if not fClosed then Close;
  newFileName := Format('%s.%d.%d.txt',[fFileName, fLinesCount, fMaxDigit]);
  if FileExists( newFileName ) then
     DeleteFile( PWideChar( newFileName ) );
  if not RenameFile( getFullFileName, newFileName ) then
    Result := 'Error: file <'+getFullFileName+'> was not renamed to'+
              ' <'+newFileName+'>. Error code=0x'+IntToHex(GetlastError, 8);
end;

{ TTmpFileList }

constructor TTmpFileList.Create(AOwnsObjects: Boolean);
begin
  inherited Create( AOwnsObjects );
  fLock    := TObject.Create;
  fCurrent := -1;
  fSorted  := False;
end;

destructor TTmpFileList.Destroy;
begin
  fLock.Free;
  inherited;
end;

function TTmpFileList.LockList: TTmpFileList;
begin
  TMonitor.Enter(FLock);
  Result := Self;
end;

procedure TTmpFileList.UnlockList;
begin
  TMonitor.Exit( FLock );
end;

procedure TTmpFileList.setFirst;
begin
  LockList;
  try
    if (Count>0) then fCurrent := 0
                 else fCurrent := -1;
  finally
    UnlockList;
  end;
end;

function TTmpFileList.getNext: TTmpFile;
begin
  LockList;
  try
    if (fCurrent < Count-1)
      then begin
             inc(fCurrent);
             Result := Items[ fCurrent ];
           end
      else begin
             fCurrent := MaxInt;
             Result := nil;
           end;
  finally
    UnlockList;
  end;
end;

procedure TTmpFileList.SortFileList;
var comp : TTmpFileComparer;
begin
  comp := TTmpFileComparer.Create;
  Sort( comp );
  FreeAndNil(comp);
  fSorted  := True;
end;

function TTmpFileList.getTmpFile(const AFileName: String): TTmpFile;

    function innerGetObject(LeftIndex, RightIndex : Integer) : TTmpFile;
    var obj : TTmpFile;
        idx, res : Integer;
    begin
      Result := nil;
      if (LeftIndex = RightIndex) then
        begin
          obj := List[ LeftIndex ];
          if AnsiCompareText(AFileName, obj.fileName)=0
             then Result := List[ LeftIndex ]
             else Result := nil;
        end else begin
                   idx := LeftIndex + ((RightIndex-LeftIndex) div 2);
                   obj := List[idx];
                   res := AnsiCompareText(AFileName, obj.fileName);
                   case res of
                     0:  Result := List[idx];
                     -1: Result := innerGetObject(LeftIndex, idx);
                     1:  Result := innerGetObject(idx+1, RightIndex);
                   end;
                 end;
    end;

begin
  if not fSorted then Result := nil  // ?raise Exception?
                 else Result := innerGetObject(0, Self.Count-1);
end;

{ TTmpFileComparer }

function TTmpFileComparer.Compare(const Left, Right: TTmpFile): Integer;
begin
  Result := AnsiCompareText(Left.fileName, Right.fileName);
end;

end.
