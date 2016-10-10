unit unCommonData;

interface
uses System.Classes;

const BIG_FILE_NAME   = 'BigFile.txt';
      DOUBLE_SPASE    = '  ';
      SINGLE_SPASE    = ' ';
      FILE_BUFF_LEN   = 32*1024;
      LETTERS_ARR_LEN = 27;
      lwrCase : array[0..LETTERS_ARR_LEN-1] of String = ('q','w','e','r','t',
                                                         'y','u','i','o','p',
                                                         'a','s','d','f','g',
                                                         'h','j','k','l','z',
                                                         'x','c','v','b','n','m',' ');
      uprCase : array[0..LETTERS_ARR_LEN-1] of String = ('Q','W','E','R','T',
                                                         'Y','U','I','O','P',
                                                         'A','S','D','F','G',
                                                         'H','J','K','L','Z',
                                                         'X','C','V','B','N','M',' ');
      uprCaseShort: array[0..26] of String = ('Q','W','E','R','T',
                                               'Y','U','I','O','P',
                                               'A','S','D','F','G',
                                               'H','J','K','L','Z',
                                               'X','C','V','B','N','M',' ');
function StrToStream(Stream : TStream; const DataStr : String) : Integer;
function getProcessorNum : Integer;

implementation

uses WinAPI.Windows,
     System.SysUtils;

function StrToStream(Stream : TStream; const DataStr : String) : Integer;
var B : TBytes;
begin
  B := TEncoding.ANSI.GetBytes( DataStr );
  Result := Stream.Write(B[0], Length(B) );
end;

function getProcessorNum : Integer;
var si : TSystemInfo;
begin
  try
    GetSystemInfo( si );
    Result := si.dwNumberOfProcessors;
  except
    Result := 1;
  end;
end;

end.
