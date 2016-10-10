unit unABCSorter;

interface

uses System.Classes,
     unFileMapping;

type
  TWordElem = record
    Str     : String;
    Len,
    tracker : Int64;
  end;

  TWordElemList = array of TWordElem;
  TLetterInfo = array of array of Int64;

  TABCStringSorter = class;

  TUnloadSortedEvent  = procedure(Stream : TStream; Sorter: TABCStringSorter; const AStr : String) of object;
  TLoadUnsortedEvent = function(Sorter: TABCStringSorter; const AStr : String): String of object;

  TABCStringSorter = class
  private
    WordTracker : TWordElemList;
    LetterTracker : TLetterInfo;
    MaxStrLen : Int64;
    fUnloadSortedEvent: TUnloadSortedEvent;
    fLoadUnsortedEvent: TLoadUnsortedEvent;
    fCount: Int64;
    fTag: Int64;
    fStream: TStream;
    procedure  UnloadSortedTrigger(const AStr : String); virtual;
    function   LoadUnsortedTrigger(const AStr : String): String; virtual;
    procedure  setWordTrackerElem(idx: Int64; const Str: String);
    procedure  initLetterTracker;
  public
    function   LoadFromStrArray(const sourceArray : array of String) : Int64;
    function   LoadFromStreamReader(const sourceStreamReader : TStreamReader; LinesCount: Int64) : Int64;
    function   LoadFromMMFReader(const sourceReader : TMMFReader; LinesCount: Int64) : Int64;
    procedure  Sort;
    procedure  Close;
    destructor Destroy; override;
    property   Stream : TStream read fStream write fStream;
    property   onUnloadSorted  : TUnloadSortedEvent  read fUnloadSortedEvent  write fUnloadSortedEvent;
    property   onLoadUnsorted : TLoadUnsortedEvent read fLoadUnsortedEvent write fLoadUnsortedEvent;
    property   Count : Int64 read fCount;
    property   Tag : Int64 read fTag write fTag;
  end;

implementation
uses System.SysUtils, System.Math;

const ABCStr : String = '. 0123456789AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz';
      ABCCount = 64;


{ TABCStringSorter }

procedure TABCStringSorter.Close;
begin
  WordTracker   := nil;
  LetterTracker := nil;
end;

destructor TABCStringSorter.Destroy;
begin
  Close;
  inherited;
end;


procedure TABCStringSorter.SetWordTrackerElem(idx : Int64; const Str : String);
begin
  WordTracker[idx].Str := LoadUnsortedTrigger( Str );
  WordTracker[idx].Len := Length( WordTracker[idx].Str );
  WordTracker[idx].tracker := -1;
  MaxStrLen := Max(MaxStrLen, WordTracker[idx].Len);
  inc(fCount);
end;

procedure TABCStringSorter.initLetterTracker;
var i, j: Int64;
begin
  SetLength(LetterTracker, ABCCount, MaxStrLen);
  for i:=0  to ABCCount-1 do
    for j:=0  to MaxStrLen-1 do
      LetterTracker[i,j] := -1;
end;

function TABCStringSorter.LoadFromStrArray(const sourceArray: array of String): Int64;
var i: Int64;
begin
  Result := Length( sourceArray );  SetLength(WordTracker, Result );
  MaxStrLen := 0;
  for i:= Low( sourceArray ) to High( sourceArray ) do
    SetWordTrackerElem(i, sourceArray[i]);
  initLetterTracker;
end;

function TABCStringSorter.LoadFromStreamReader(const sourceStreamReader: TStreamReader;
                                                     LinesCount: Int64): Int64;
begin
  Result := 0; SetLength(WordTracker, LinesCount);
  MaxStrLen := 0;
  repeat
    SetWordTrackerElem(Result, sourceStreamReader.ReadLine);
    inc( Result );
  until ( sourceStreamReader.EndOfStream ) or
        (Result = LinesCount);
  initLetterTracker;
end;

function TABCStringSorter.LoadFromMMFReader(const sourceReader: TMMFReader;
                          LinesCount: Int64): Int64;
var s : String;
begin
  Result := 0; SetLength(WordTracker, LinesCount );
  MaxStrLen := 0;
  repeat
    s := sourceReader.ReadLine;
    SetWordTrackerElem(Result, s);
    inc( Result );
  until ( sourceReader.EndOfFile ) or
        (Result = LinesCount);
  initLetterTracker;
end;



procedure TABCStringSorter.Sort;

    procedure ProcessNextLevel(StartTracker, Level : Int64);
    var i, ChIdx, WdIdx : Int64;
        Ch : Char;
        tr, current_tracker : Int64;
    begin
      current_tracker := StartTracker;
      if WordTracker[current_tracker].Len=Level then Exit;

      while current_tracker<>-1 do
        begin
          tr    := WordTracker[current_tracker].tracker;
          Ch    := WordTracker[current_tracker].Str[Level+1];
          ChIdx := ABCStr.IndexOf( Ch );
          WordTracker[current_tracker].tracker := LetterTracker[ChIdx, Level];
          LetterTracker[ChIdx, Level] := current_tracker;
          current_tracker := tr;
          if WordTracker[current_tracker].Len=Level then break;
        end;

      for i:=Low( LetterTracker ) to High( LetterTracker ) do
        if LetterTracker[i, Level]<>-1 then
          begin
            WdIdx := LetterTracker[i, Level];
            if WordTracker[WdIdx].tracker<>-1 then
              begin
                LetterTracker[i, Level] := -1;
                ProcessNextLevel(WdIdx, Level+1);
              end else begin
                         UnloadSortedTrigger( WordTracker[WdIdx].Str );
                         LetterTracker[i, Level] := -1;
                       end;
          end;
    end;

var i, w, col, row, char_idx, word_idx : Int64;
    Ch : Char;

begin
  // process 0 level
  for w:=Low(WordTracker) to High(WordTracker) do
    begin
      Ch := WordTracker[w].Str[1];
      char_idx := ABCStr.IndexOf( Ch );
      WordTracker[w].tracker := LetterTracker[char_idx, 0];
      LetterTracker[char_idx, 0] := w;
    end;

  // process other levels
  for i:=Low( LetterTracker ) to High( LetterTracker ) do
    if LetterTracker[i, 0]<>-1 then
      begin
        word_idx := LetterTracker[i, 0];
        LetterTracker[i, 0] := -1;
        ProcessNextLevel(word_idx, 1);

        // output sorted
        for row:=High( LetterTracker[0] ) downto 1 do
          for col:=Low( LetterTracker ) to High( LetterTracker ) do
            if LetterTracker[col, row]<>-1 then
              begin
                word_idx := LetterTracker[col, row];
                UnloadSortedTrigger( WordTracker[word_idx].Str );
                LetterTracker[col, row] := -1;
              end;
      end;
end;

procedure TABCStringSorter.UnloadSortedTrigger(const AStr: String);
begin
  if Assigned( fUnloadSortedEvent )
     then fUnloadSortedEvent(fStream, Self, AStr)
     else WriteLn(AStr);
end;

function TABCStringSorter.LoadUnsortedTrigger(const AStr: String): String;
begin
  if Assigned( fLoadUnsortedEvent )
     then Result := fLoadUnsortedEvent(Self, AStr)
     else Result := AStr;
end;

end.
