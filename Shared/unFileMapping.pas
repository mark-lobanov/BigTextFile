unit unFileMapping;

interface

uses WinAPI.Windows,
     System.SysUtils;

const FILE_NOT_WRITTEN    = 0;
      FILE_WRITE_OVERFLOW = $FF000001;
      FILE_IS_EMPTY       = $FF000002;
type

  TMMFReader = class
  private
    hFile,
    hFileMapObj: THandle;
    lpBaseAddress: Pointer;
    fMapSize,
    cbSize,
    cbWindowsSize: Int64;
    fFileName,
    fErrorEntry, tail : String;
    fEncoding : TEncoding;

    fPosition,
    cbReadInMap,
    cbRead : Int64;

    lastByte : Byte;
    fLinesCount: Int64;

    function  getEndOfFile: Boolean;
    procedure internalClear;
  public
    constructor Create;
    destructor  Destroy; override;
    function    Open(const aFileName: string; aEncoding: TEncoding; MapSize : Int64 = 0): DWORD;
    function    ReadLine: String;
    procedure   Close;

    property Size:       Int64   read cbSize;
    property LinesCount: Int64   read fLinesCount;
    property EndOfFile:  Boolean read getEndOfFile;
    property ErrorEntry : String read fErrorEntry;
  end;

  TFlushMode = (bfmNone,         // on Windows discretion
                bfmFlushCycle,   // every map view end
                bfmFlushEnd);    // at closing

  TMMFWriter = class
  private
    fFileName,
    fErrorEntry : String;
    hFile,
    hFileMapObj: THandle;
    lpBaseAddress: Pointer;
    fMaxFileSize: NativeInt;
    fTrimFileSize: Boolean;
    fFlushMode: TFlushMode;

    cbWritten,
    cbWrittenInMap : NativeInt;
    fEndOfFile : Boolean;
    function CreateMap : DWORD;

  public
    procedure Close;
    function  WriteStr(const Str : String) : NativeInt;
    function  WriteStrLn(const Str : String) : NativeInt;

    constructor Create(const FileName : String; MaxFileSize : NativeUInt; TrimFileSize : Boolean = True; FlushMode : TFlushMode = bfmFlushEnd);
    destructor  Destroy; override;

    property EndOfFile : Boolean read fEndOfFile;
    property bytesWritten : NativeInt read cbWritten;
    property ErrorEntry : String read fErrorEntry;
  end;

  EMMFIOException = class(Exception)
  end;

  EMMFWriteException = class(EMMFIOException)
  end;

  EMMFCreateException = class(EMMFIOException)
  end;

  EMMFOpenException = class(EMMFIOException)
  end;

var DEFAULT_MAP_SIZE : Cardinal;

implementation
uses System.Math;


function AllocationGranularity : Cardinal;
var si : TSystemInfo;
begin
  try
    GetSystemInfo( si );
    Result := si.dwAllocationGranularity;
  except
    Result := 64*1024;
  end;
end;

function Int64Low(Value : Int64) : DWORD;
begin
  Result := DWORD(Value and $00000000FFFFFFFF);
end;

function Int64High(Value : Int64) : DWORD;
begin
  Result := DWORD(Value shr 32);
end;

function IncPtr(P : Pointer; toAdd : NativeInt): Pointer;
begin
  Result := Pointer( NativeInt(P) + toAdd );
end;

function AnsiStrToPtr(const AStr : String; P : Pointer) : NativeInt;
var bTmp : TBytes;
begin
 Result := 0;
 if (AStr.IsEmpty) and Assigned(P) then
   begin
     bTmp := TEncoding.ANSI.GetBytes( AStr );
     Result := Length(bTmp);
     Move( bTmp[0], P^, Result );
   end;
end;



{ TMMFReader }

constructor TMMFReader.Create;
begin
  inherited Create;
  InternalClear;
//  F_hFile := INVALID_HANDLE_VALUE;
//  F_pData := nil;
//  OpenForRead(aFileName);
end;

destructor TMMFReader.Destroy;
begin
  Close;
  inherited;
end;

procedure TMMFReader.internalClear;
begin
  lpBaseAddress := nil;
  hFileMapObj          := 0;
  hFile         := INVALID_HANDLE_VALUE;
  fErrorEntry   := '';
end;

procedure TMMFReader.Close;
begin
  if (lpBaseAddress <> nil) then UnmapViewOfFile(lpBaseAddress);
  if (hFileMapObj <> 0)            then CloseHandle(hFileMapObj);
  if (hFile <> INVALID_HANDLE_VALUE) then CloseHandle(hFile);
  InternalClear;
end;

function TMMFReader.Open(const aFileName: string; aEncoding: TEncoding; MapSize : Int64 = 0): DWORD;
var FileSizeHigh : Cardinal;
begin
  InternalClear;
  Result    := 0;
  fFileName := aFileName;
  fEncoding := aEncoding;


  if (aFileName <> EmptyStr)then
    begin
       hFile:= CreateFile(PChar(aFileName),GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
       if (hFile <> INVALID_HANDLE_VALUE)then
         begin
            cbSize := GetFileSize(hFile, @FileSizeHigh);
            cbSize := cbSize + (Int64(FileSizeHigh) shl 32);
            if cbSize<>0 then
              begin
                hFileMapObj := CreateFileMapping(hFile, nil, PAGE_READONLY, Int64High(cbSize), Int64Low(cbSize), nil);
                if (hFileMapObj<>0)then
                  begin
                     if MapSize=0 then fMapSize  := 0
                                  else fMapSize  := Min(cbSize, MapSize);

                     lpBaseAddress := MapViewOfFile(hFileMapObj, FILE_MAP_READ, 0, 0, fMapSize ); //***
                     if (lpBaseAddress <> nil)then
                     begin
                        case fMapSize of
                          0:   cbWindowsSize := cbSize;
                          else cbWindowsSize := Min(cbSize, MapSize);
                        end;
                        cbReadInMap := 0;
                        cbRead      := 0;
                        fLinesCount := 0;

                        fPosition   := 0;
                        lastByte    := 0;
                        Exit;  // normal Exit
                     end else begin fErrorEntry := 'TMMFReader.CreateMap.MapViewOfFile'; Result := GetLastError; CloseHandle(hFileMapObj); CloseHandle(hFile); end;
                  end else begin fErrorEntry := 'TMMFReader.CreateMap.CreateFileMapping'; Result := GetLastError; CloseHandle(hFile); end;
              end else begin fErrorEntry := 'TMMFReader.CreateMap.CreateFile. File '+fFileName+' is empty'; Result := FILE_IS_EMPTY; end;
         end else begin fErrorEntry := 'TMMFReader.CreateMap.CreateFile(for reading)'; Result := GetLastError; end;

    end else begin fErrorEntry := 'TMMFReader.OpenForRead: FileName is empty'; end;

  if (Result<>0) or (fErrorEntry<>EmptyStr) then
     raise EMMFOpenException.Create(fErrorEntry+' Win32 error: 0x'+IntToHex(Result, 8));
end;


function TMMFReader.getEndOfFile: Boolean;
begin
  Result := cbRead >= cbSize;
end;

function TMMFReader.ReadLine: String;
var b : Byte;

    function makeResult : String;
    var ar : TBytes;
        startByte : PByte;
    begin
      startByte := IncPtr(lpBaseAddress, fPosition);
      ar        := BytesOf( startByte, cbReadInMap-fPosition );
      Result    := fEncoding.GetString( ar, 0, Length(ar) );
    end;

begin
  Result := '';

  while cbReadInMap <= cbWindowsSize do
    begin

      if cbReadInMap = cbWindowsSize then
        begin
          // end of file
          if cbRead = cbSize then
            begin
              Result := makeResult;
              inc(fLinesCount);
              Exit;
            end else begin
                       // end of view but not EOF
                       if fPosition < cbReadInMap then
                          tail := makeResult;
                       UnMapViewOfFile(lpBaseAddress); lpBaseAddress := nil;
                       fPosition   := 0;
                       cbReadInMap := 0;

                       cbWindowsSize := Min(cbSize-cbRead, fMapSize);
                       lpBaseAddress := MapViewOfFile(hFileMapObj, FILE_MAP_READ, Int64High(cbRead), Int64Low(cbRead), cbWindowsSize );
                     end;
        end;

      if lpBaseAddress=nil then
         raise Exception.Create('Error lpBaseAddress=nil!!! cbRead='+IntToStr(cbRead)+' FileName='+fFileName+' Position='+IntToStr(fPosition) );

      b := PByte( IncPtr(lpBaseAddress, cbReadInMap) )^;

      if b=$0A then
        begin

          if tail<>'' then
            begin
              if lastByte=$0D then
                begin
                  if cbReadInMap=0
                     then begin
                            Result := Copy(tail,1, length(tail)-1);
                            dec(cbReadInMap);
                          end
                     else begin
                            dec(cbReadInMap);
                            Result := tail + makeResult;
                          end;
                end;
              tail   := '';
              if (lastByte=$0D) then
                 inc(cbReadInMap);
            end else begin
                       if lastByte=$0D then
                          dec(cbReadInMap);
                       if cbReadInMap>0 then
                       Result := makeResult;
                       if lastByte=$0D then
                          inc(cbReadInMap);
                     end;

          inc(cbReadInMap);
          inc(cbRead);
          fPosition := cbReadInMap;
          lastByte := b;
          inc(fLinesCount);
          Exit;
        end else

        begin
          inc(cbReadInMap);
          inc(cbRead);
          lastByte := b;
        end;
    end;

end;



{ TMMFWriter }

constructor TMMFWriter.Create(const FileName: String; MaxFileSize: NativeUInt;  TrimFileSize: Boolean = True; FlushMode : TFlushMode = bfmFlushEnd);
var res: dword;
begin
  inherited Create;
  fFileName   := FileName;
  fErrorEntry := EmptyStr;
  hFile       := INVALID_HANDLE_VALUE;
  hFileMapObj := INVALID_HANDLE_VALUE;
  lpBaseAddress := nil;
  fMaxFileSize  := MaxFileSize;
  fTrimFileSize := TrimFileSize;
  fFlushMode    := FlushMode;

  res := CreateMap;
  if res<>0 then raise EMMFCreateException.Create(fErrorEntry+': File or map wasn''t created. Win32 error: 0x'+IntToHex(Res, 8));
end;

function TMMFWriter.CreateMap: DWORD;
begin
  if FileExists( fFileName ) then DeleteFile( fFileName );

  hFile := CreateFile(PWideChar( fFileName ),
                      GENERIC_READ or GENERIC_WRITE,
                      FILE_SHARE_READ, nil,
                      CREATE_ALWAYS, 0, 0);
  if hFile<>INVALID_HANDLE_VALUE then
    begin
      hFileMapObj := CreateFileMapping(hFile, Nil, PAGE_READWRITE,
                                       Int64High(fMaxFileSize),
                                       Int64Low(fMaxFileSize), nil);
      if hFileMapObj<>0 then
        begin
          lpBaseAddress := MapViewOfFile(hFileMapObj, FILE_MAP_READ or FILE_MAP_WRITE, 0, 0, DEFAULT_MAP_SIZE);
          if Assigned(lpBaseAddress) then
            begin
              cbWritten      := 0;
              cbWrittenInMap := 0;
              fEndOfFile     := False;
              Result := 0;
            end else begin fErrorEntry := 'TMMFWriter.CreateMap.MapViewOfFile'; Result := GetLastError; CloseHandle(hFileMapObj); CloseHandle(hFile); end;
        end else begin fErrorEntry := 'TMMFWriter.CreateMap.CreateFileMapping'; Result := GetLastError; CloseHandle(hFile); end;
    end else begin fErrorEntry := 'TMMFWriter.CreateMap.CreateFile'; Result := GetLastError; end;

end;

destructor TMMFWriter.Destroy;
begin
  Close;
  inherited;
end;


function TMMFWriter.WriteStr(const Str: String): NativeInt;
var strLn,
    part1, part2 : NativeInt;
begin
  strLn  := Length( Str );
  if strLn=0 then begin Result := FILE_NOT_WRITTEN; Exit; end;

  // File owerflow
  if (cbWritten + strLn) > fMaxFileSize then
     begin
       fEndOfFile := True;
       Result     := NativeInt(FILE_WRITE_OVERFLOW);
     end else
  // Map view owerflow
  if (cbWrittenInMap + strLn) > NativeInt(DEFAULT_MAP_SIZE) then
    begin
      part1 := NativeInt(DEFAULT_MAP_SIZE) - cbWrittenInMap;
      part2 := strLn - part1;
      AnsiStrToPtr( Copy(Str, 1, part1), lpBaseAddress);
      inc(cbWrittenInMap, part1); inc(cbWritten, part1);
      // close existing view of file mapping
      if fFlushMode=bfmFlushCycle then
         FlushViewOfFile(lpBaseAddress, DEFAULT_MAP_SIZE);
      UnMapViewOfFile(lpBaseAddress); lpBaseAddress := nil;
      // creatin new (next) view of file mapping
      lpBaseAddress := MapViewOfFile(hFileMapObj,
                                     FILE_MAP_READ or FILE_MAP_WRITE,
                                     Int64High(cbWritten), Int64Low(cbWritten), DEFAULT_MAP_SIZE);
      if Assigned( lpBaseAddress ) then
        begin
          AnsiStrToPtr( Copy(Str, part1+1, part2), lpBaseAddress);
          lpBaseAddress  := IncPtr(lpBaseAddress, part2);
          cbWrittenInMap := part2;
          inc(cbWritten, part2);
        end else begin
                   fErrorEntry := 'TMMFWriter.WriteStr: MapViewOfFile (remap) error 0x'+IntToHex(NativeInt(GetLastError)*(-1), 8) +
                                  ' part1:'+IntToStr(part1) +
                                  ' part2:'+IntToStr(part2) +
                                  ' strLen:'+IntToStr(strLn) +
                                  ' cbWritten:'+IntToStr(cbWritten) +
                                  ' cbWrittenInMap:'+IntToStr(cbWrittenInMap);
                   raise EMMFWriteException.Create(fErrorEntry);
                 end;
      Result := strLn;
    end else begin
               // regular write
               AnsiStrToPtr( Str, lpBaseAddress );
               lpBaseAddress := IncPtr(lpBaseAddress, strLn);
               inc(cbWrittenInMap, strLn); inc(cbWritten, strLn);
               Result := strLn;
             end;
end;

function TMMFWriter.WriteStrLn(const Str: String): NativeInt;
begin
  Result := WriteStr( Str + sLineBreak );
end;

procedure TMMFWriter.Close;
var dw : DWORD;
begin
  try
    if fFlushMode=bfmFlushEnd then
       FlushViewOfFile(lpBaseAddress, 0);
    UnMapViewOfFile(lpBaseAddress); lpBaseAddress := nil;
    CloseHandle(hFileMapObj);       hFileMapObj := INVALID_HANDLE_VALUE;
    if fTrimFileSize then
      begin
        // trim file
        dw := Int64High( cbWritten );
        SetFilePointer(hFile, Int64Low( cbWritten ), @dw, FILE_BEGIN);
        SetEndOfFile(hFile);
      end;
  finally
    // close file
    CloseHandle(hFile); hFile := INVALID_HANDLE_VALUE;
  end;
end;

initialization
  DEFAULT_MAP_SIZE := AllocationGranularity;

end.
