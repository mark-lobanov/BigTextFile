unit Test_unABCSorter;
{

  Delphi DUnit Test Case
  ----------------------
  This unit contains a skeleton test case class generated by the Test Case Wizard.
  Modify the generated code to correctly setup and call the methods from the unit
  being tested.

}

interface

uses
  TestFramework, unABCSorter, unFileMapping, System.Classes;

type
  // Test methods for class TABCStringSorter

  TestTABCStringSorter = class(TTestCase)
  strict private
    FABCStringSorter: TABCStringSorter;
  private
    testString : String;
    function LoadToStreamProc(Sorter: TABCStringSorter; const AStr: String): String;
    procedure WriteToStreamProc(Sorter: TABCStringSorter; const AStr: String);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadFromStrArray;
    procedure TestSort;
  end;

implementation
uses System.SysUtils;

const sourceArray : array[0..4] of String = ( 'Apple.  415',
                                              'Something something something.30432',
                                              'Apple.    1',
                                              'Cherry is the best.   32',
                                              'Banana is yellow.    2');

procedure TestTABCStringSorter.SetUp;
begin
  FABCStringSorter := TABCStringSorter.Create;
  FABCStringSorter.onLoadUnsorted := LoadToStreamProc;
  FABCStringSorter.onUnloadSorted := WriteToStreamProc;
end;

procedure TestTABCStringSorter.TearDown;
begin
  FreeAndNil( FABCStringSorter );
end;

procedure TestTABCStringSorter.TestLoadFromStrArray;
var ReturnValue, Ln: Int64;
begin
  Ln := Length(sourceArray);
  ReturnValue := FABCStringSorter.LoadFromStrArray(sourceArray);
  CheckEquals(Ln, ReturnValue, 'ActualVaue='+IntToStr(Ln) );
end;


function TestTABCStringSorter.LoadToStreamProc(Sorter: TABCStringSorter; const AStr: String): String;
var ar: TArray<String>;
begin
  ar     := AStr.Split(['.']);
  Result := ar[0] + '.' + Format( '%'+IntToStr(Sorter.Tag)+'s',[ar[1]] );
end;

procedure TestTABCStringSorter.WriteToStreamProc(Sorter: TABCStringSorter; const AStr: String);
var ar: TArray<String>;
    s : String;
begin
  ar := AStr.Split(['.']);
  s  := Trim(ar[1])+'. '+ar[0];
  testString := testString + s + sLineBreak;
end;

procedure TestTABCStringSorter.TestSort;
const ethalon : String = '1. Apple'#$D#$A+
                         '415. Apple'#$D#$A+
                         '2. Banana is yellow'#$D#$A+
                         '32. Cherry is the best'#$D#$A+
                         '30432. Something something something'#$D#$A;
begin
  testString := EmptyStr;
  FABCStringSorter.LoadFromStrArray(sourceArray);
  FABCStringSorter.Sort;
  CheckEqualsString(testString,ethalon, 'Actual="'+testString+'"');
end;

initialization
  // Register any test cases with the test runner
  RegisterTest(TestTABCStringSorter.Suite);
end.
