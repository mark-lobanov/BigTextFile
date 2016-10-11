{$APPTYPE CONSOLE}
program BigFileGenerator;

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.StrUtils,
  unCommonData in '..\Shared\unCommonData.pas';

const STR_MAX_LEN    = 10;                        // Max length of string w/o number
      DUBS_COUNT     = 10;
      SB_STR_COUNT   = 3200;                      // ~FILE_BUFF_LEN/STR_LEN
      DUBS_NAME      = '.DuplicatedStrings.txt';
      PROMPT_MESSAGE = 'Please, enter file size in GB (positive int): ';

function randomString(aLen : Integer) : String;
var i, cnt, minLen : Integer;
    tmp : String;
begin
  Result := EmptyStr;

  minLen := Round( aLen*0.7 ); // minimum string length is -30%
  cnt    := RandomRange (minLen, aLen);

  while (Length(Result) < minLen) do
    begin
      for i := 1 to cnt do
        begin
          case Random( 2 ) of
            0: tmp := lwrCase[ Random( LETTERS_ARR_LEN ) ];
            1: tmp := uprCase[ Random( LETTERS_ARR_LEN ) ];
          end;
          Result := Result + tmp;
        end;
      // removing double spaces
      while Result.Contains( DOUBLE_SPASE ) do
        Result := ReplaceText(Result, DOUBLE_SPASE, SINGLE_SPASE);
    end;

  if Result.StartsWith( SINGLE_SPASE ) or Result.EndsWith( SINGLE_SPASE ) then
     Result := Trim( Result );
end;


function dupsFileName: String;
begin
  Result := ChangeFileExt(BIG_FILE_NAME, DUBS_NAME);
end;


procedure progressMessage(currenSize, allSize : int64; var savePercent : Integer; startTime : TDateTime);
var currPercent : Integer;
begin
  currPercent := Round( currenSize/allSize*100 );
  if ((currPercent mod 10) = 0) and
      (currPercent <> savePercent) and
      (currPercent <> 0) then
    begin
      Writeln(TimeToStr( time-startTime ),' ', currPercent, '% done');
      savePercent := currPercent;
    end;
end;

var cnt, cbWritten, specifiedFileSize : Int64;
    tmpPercent : Integer;
    dupStrings : TStringList;
    sb : TStringBuilder;
    st: TBufferedFileStream;
    s : String;
    t : TDateTime;


begin
{$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
  Randomize;

  t := time; tmpPercent := -1; cbWritten := 0;
  Write(PROMPT_MESSAGE); ReadLn(specifiedFileSize);

//  specifiedFileSize := specifiedFileSize*1024*1024;      // in megabytes (for test)
  specifiedFileSize := specifiedFileSize*1024*1024*1024; // in gigabytes

  dupStrings := TStringList.Create;
  for cnt := 1 to DUBS_COUNT do dupStrings.Add( randomString( STR_MAX_LEN ) );
  dupStrings.SaveToFile( dupsFileName );

  sb := TStringBuilder.Create( Round(STR_MAX_LEN * SizeOf(Char) * SB_STR_COUNT * 1.2) );
  st := TBufferedFileStream.Create(BIG_FILE_NAME, fmCreate, FILE_BUFF_LEN);
  try
    cnt := 1;
    repeat
      // generate random string
      // ~0.01% are duplicated strings
      if (cnt mod Round( specifiedFileSize*0.001 ))=0
        then s := dupStrings[ Random( dupStrings.Count ) ]
        else s := randomString( STR_MAX_LEN );

      s := cnt.ToString + '. ' + s + sLineBreak;
      sb.Append( s );

      inc(cbWritten, Length(s) ); inc(cnt);

      // console progress message every 10% of output file size
      progressMessage(cbWritten, specifiedFileSize, tmpPercent, t);

      // flush strings to file
      // at the end of mail cycle or every SB_STR_COUNT cycles
      if (cbWritten >= specifiedFileSize) or ((cnt mod SB_STR_COUNT) = 0) then
        begin
          StrToStream(st, sb.ToString );
          sb.Clear;
        end;

    until cbWritten >= specifiedFileSize;

    st.FlushBuffer;
  finally
    FreeAndNil( sb );
    FreeAndNil( st );
  end;

  FreeAndNil( dupStrings );
  Writeln('Total time: ', TimeToStr(time-t));
end.
