unit unUtils;

interface
uses System.Classes,
     unABCSorter;

const CHARS_IN_NAME = 2;
      MSG_TMP_FILES_CREATED       = ': %d temporary files was created';
      MSG_LINES_PROCESSED         = ': %s lines processed';
      MSG_SEPARATING_COMPLETE     = ': Separating complete! %s lines were put into output stream';
      MSG_FILES_PREPARED          = ': %d temporery files are prepared to sorting! %s lines written';
      MSG_SORTING_COMPLETE        = ': sorting complete';
      MSG_FINISH                  = 'Total time: ';
      MSG_ERR_TMP_FILE_PARAMS     = 'Error in parameters for file %s';
      MSG_ERR_BIGFILE_NOT_EXISTS  = 'The file <%s> does not exist in current directory. Exiting...';
      MSG_ERR_INPUT_FILE_OPEN     = 'Error! Input file open failed! Error: %s';
      MSG_WARN_TEMPLATE_NOT_FOUND = 'Warning: file template not found for string <%s>';

type
  TDummy = class
  public
    class procedure WriteToStreamProc(Stream : TStream; Sorter: TABCStringSorter; const AStr : String);
    class function LoadProc(Sorter: TABCStringSorter; const AStr : String) : String;
  end;

function sortedFileName: String;
function getLinesCountAndMaxDidgit(const FileName : String; var LinesCount: Int64; var MaxDidgit: integer) : Boolean;

implementation
uses System.SysUtils,
     unCommonData;

function sortedFileName: String;
var a : TArray<String>;
begin
  a := BIG_FILE_NAME.Split( ['.'] );
  Result := a[0]+'.Sorted.txt';
end;

function getLinesCountAndMaxDidgit(const FileName : String; var LinesCount: Int64; var MaxDidgit: integer) : Boolean;
var ar: TArray<String>;
begin
  try
    ar := FileName.Split(['.']);
    LinesCount := StrToInt64( ar[1] );
    MaxDidgit  := StrToInt( ar[2] );
    Result := True;
  except
    Result := False;
  end;
end;


{ TDummy }

class function TDummy.LoadProc(Sorter: TABCStringSorter; const AStr: String): String;
var ar: TArray<String>;
begin
  ar := AStr.Split(['.']);
  // max digits value stored in Sorter.Tag
  Result := ar[0] + '.' + Format( '%'+IntToStr(Sorter.Tag)+'s',[ar[1]] );
end;

class procedure TDummy.WriteToStreamProc(Stream : TStream; Sorter: TABCStringSorter; const AStr: String);
var B : TBytes;
    ar: TArray<String>;
begin
  ar := AStr.Split(['.']);

  B := TEncoding.ANSI.GetBytes( Trim(ar[1])+'. '+ar[0]+sLineBreak );
  Stream.Write(B[0], Length(B) );
end;


end.
