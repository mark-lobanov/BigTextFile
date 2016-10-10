{$APPTYPE CONSOLE}
program BigFileSorter;

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  unFileMapping in '..\Shared\unFileMapping.pas',
  unCommonData in '..\Shared\unCommonData.pas',
  unABCSorter in 'unABCSorter.pas',
  unTmpFile in 'unTmpFile.pas',
  unUtils in 'unUtils.pas';

var tmpFiles : TTmpFileList;

procedure processTmpFile;
var tmpFile : TTmpFile;
    s : String;
    sz : Int64;
    md : Integer;
    rd : TMMFReader;
    sorter : TABCStringSorter;
    dummy : TDummy;
begin
  // getting next describer with list locking
  tmpFile := tmpFiles.getNext;
  if Assigned(tmpFile) then
    begin
      s := tmpFile.intermediateFileName;
      if s<>EmptyStr then
        begin
          if getLinesCountAndMaxDidgit(s, sz, md) then
          begin
            dummy := TDummy.Create;
            rd    := TMMFReader.Create;
            try
              if rd.Open( s, TEncoding.ANSI)=0 then
                begin
                  sorter     := TABCStringSorter.Create;
                  try
                    sorter.Tag := md;
                    sorter.onLoadUnsorted := dummy.LoadProc;
                    sorter.onUnloadSorted := dummy.WriteToStreamProc;
                    sorter.LoadFromMMFReader(rd, sz);
                    // file stream for output
                    sorter.Stream := TBufferedFileStream.Create(tmpFile.sortedFileName,
                                                              fmCreate, FILE_BUFF_LEN);
                    // sorting and writing output file
                    try
                      sorter.Sort;
                    finally
                      sorter.Stream.Free;
                    end;
                  finally
                    FreeAndNil( sorter );
                  end;
                end else Writeln( rd.ErrorEntry );
            finally
              FreeAndNil( rd );
              DeleteFile( PWideChar( s ) );
              FreeAndNil( dummy );
            end;
          end else Writeln( Format(MSG_ERR_TMP_FILE_PARAMS, [s]) );
        end;
    end;
end;

procedure processFiles(List : TTmpFileList; TaskCount : Integer);
var workers : array of ITask;
    worker : ITask;
    i, ctFinished, arrSize : Integer;
begin
  ctFinished := 0;
  while (ctFinished < List.Count) do
    begin
      // initialization
      if (ctFinished+TaskCount < List.Count)
         then arrSize := TaskCount
         else arrSize := List.Count - ctFinished;

      SetLength(workers, arrSize);
      // threads (tasks) creating
      for i:=Low( workers ) to High( workers ) do
          workers[i] := TTask.Create( processTmpFile );
      // threads (tasks) starting
      for worker in workers do
          worker.Start;
      // waing for all threads (tasks) finishing
      TTask.WaitForAll( workers );
      // finalization
      for i:=Low( workers ) to High( workers ) do
          workers[i] := nil;
      inc(ctFinished, Length( workers ));
      SetLength(workers, 0);
    end;
end;

var dst, src : TBufferedFileStream;
    tf : TTmpFile;
    linesCount : Int64;
    mainRd : TMMFReader;
    i : Integer;
    S : String;
    t : TDateTime;

begin
{$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}

  if not FileExists( BIG_FILE_NAME ) then
    begin
      Writeln( Format(MSG_ERR_BIGFILE_NOT_EXISTS, [BIG_FILE_NAME]) );
      Exit;
    end;

  // initialization, creating intermediate files
  t := time;
  tmpFiles := TTmpFileList.Create;
  try
    makeTmpFileNames(tmpFiles, '~', CHARS_IN_NAME); // 2 symbols per file name
    tmpFiles.SortFileList;
    Writeln(TimeToStr(time-t), Format(MSG_TMP_FILES_CREATED, [tmpFiles.Count]) );

    // *** main file seperating by tmp files
    linesCount := 0;
    mainRd := TMMFReader.Create;
    try
      if (mainRd.Open(BIG_FILE_NAME, TEncoding.ANSI, DEFAULT_MAP_SIZE) = 0) then
        begin
          repeat
            s   := mainRd.ReadLine;
            tf  := tmpFiles.getTmpFile( '~' + AnsiUpperCase( Copy(s, Pos('. ', s)+2, CHARS_IN_NAME ) ) );

            if Assigned(tf) then
              begin
                tf.WriteLn( s );
                inc( linesCount );
              end else Writeln(TimeToStr(time-t), Format(MSG_WARN_TEMPLATE_NOT_FOUND, [s]));

            // display progress every NNN lines
            if (linesCount mod 100000)=0 then
               Writeln(TimeToStr(time-t), Format(MSG_LINES_PROCESSED, [FloatToStrF(linesCount, ffNumber, 20, 0)]) );

          until mainRd.EndOfFile;
          mainRd.Close;
        end else raise Exception.Create( Format(MSG_ERR_INPUT_FILE_OPEN, [mainRd.ErrorEntry]) );
    finally
      FreeAndNil( mainRd );
    end;
    Writeln(TimeToStr(time-t), Format(MSG_SEPARATING_COMPLETE, [FloatToStrF(linesCount, ffNumber, 20, 0)] ) );


    // intermediate files closing, flushing buffers
    linesCount := 0;
    for i:=0 to tmpFiles.Count-1 do
      begin
        tf := TTmpFile( tmpFiles[i] );
        tf.Close;
        s := tf.RenameTmpFile;
        if (s <> EmptyStr) then
          Writeln(TimeToStr(time-t),': ' + s);
        inc(linesCount, tf.linesCount);
      end;
    Writeln(TimeToStr(time-t), Format(MSG_FILES_PREPARED, [tmpFiles.Count, FloatToStrF(linesCount, ffNumber, 20, 0)]) );


    // intermediate files sorting
    processFiles(tmpFiles, getProcessorNum*4);
    Writeln(TimeToStr(time-t), MSG_SORTING_COMPLETE);


    // merging sorted files into main output file
    dst := TBufferedFileStream.Create(sortedFileName, fmCreate, FILE_BUFF_LEN);
    try
      for i:=0 to tmpFiles.Count-1 do
        begin
          s := tmpFiles[i].sortedFileName;
          src := TBufferedFileStream.Create(s, fmOpenRead, FILE_BUFF_LEN);
          try
            if src.Size>0 then
               dst.CopyFrom(src, src.Size);
          finally
            FreeAndNil( src );
            DeleteFile( PWideChar(s) );
          end;
        end;
    finally
      FreeAndNil( dst );
    end;

  finally
    // common free memory
    FreeAndNil( tmpFiles );
  end;
  Writeln(MSG_FINISH, TimeToStr(time-t) );
end.
