@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
REM postprocess_from_obs.cmd -- video postprocessing called by OBS

rem --------------------------------------------------------
REM If your ffmpeg isn't in the PATH, remove the REM from the
REM second SET ffmpeg=... line and change the path accordingly.
SET ffmpeg=ffmpeg.exe
REM SET ffmpeg=C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe
rem --------------------------------------------------------

    if "%~1"=="" goto :help
    if "%~1"=="process" goto process

    rem read command line
    set script=%~f0

    set source=%~1
    set destdir=%~2

    set xpos=%3
    set ypos=%4
    set width=%5
    set height=%6
    set start=%7
    set length=%8
    set fps=%9
    shift /8
    set ext=%9
    shift /8
    set colors=%9
    shift /8
    set variated=%9
    shift /8
    set audio=%9

    set source=%source:/=\%
    set destdir=%destdir:/=\%
    set outputdir=%destdir%\%~n1

    rem log calls
    >>"%destdir%\%~n0.log" echo %*

    md "%outputdir%" 1>nul 2>nul
    if not exist "%outputdir%" (
        echo Unable to create output directory "%outputdir%"
        goto help
    )

    set again=%outputdir%\process_again.cmd

    rem create process_again.cmd in outputdir for manual direct postprocessing
     >"%again%" echo set source=%source%
    >>"%again%" echo set outputdir=%outputdir%
    >>"%again%" echo set xpos=%xpos%
    >>"%again%" echo set ypos=%ypos%
    >>"%again%" echo set width=%width%
    >>"%again%" echo set height=%height%
    >>"%again%" echo set start=%start%
    >>"%again%" echo set length=%length%
    >>"%again%" echo set fps=%fps%
    >>"%again%" echo set ext=%ext%
    >>"%again%" echo set colors=%colors%
    >>"%again%" echo set variated=%variated%
    >>"%again%" echo set audio=%audio%
    >>"%again%" echo "%script%" process

    start "OBS custom postprocessing" "%script%" process

goto :eof


:help
    echo postprocess_from_obs.cmd -- video postprocessing called by OBS
    echo.
    echo Usage:
    echo   postprocess_from_obs.cmd ^<video file^> ^<destdir^> ^<xpos^> ^<ypos^> ^<width^> ^<height^> ^<start^> ^<length^> ^<fps^> ^<video type^> ^<gif colors^> ^<variated length^> ^<audio^>
    echo.
goto :eof


rem Do actual processing. Configuration is from environment variables.
:process

    if "%outputdir%"=="" (
        echo Error: no outputdir given
        goto help
    )

    cd /d "%outputdir%"

    set log=ffmpeg.log
    set log=nul

    echo outputdir=%outputdir%

    echo source=%source%
    echo xpos=%xpos%
    echo ypos=%ypos%
    echo width=%width%
    echo height=%height%
    echo start=%start%
    echo length=%length%
    echo fps=%fps%
    echo ext=%ext%
    echo colors=%colors%
    echo variated=%variated%
    echo audio=%audio%

    del "%log%" 1>nul 2>nul

    rem gif exactly according to given values
    call :create_video %start% %length% %fps%

    if "%variated%"=="true" (

        rem some fps variants if gif
        rem  ----------------------------------
        call :create_video %start% %length% 5
        call :create_video %start% %length% 10
        call :create_video %start% %length% 20
        call :create_video %start% %length% 30

        rem some more variants if gif
        call :create_video %start%  5 30
        call :create_video %start%  5 20
        call :create_video %start%  5 10
        call :create_video %start%  5  5

        call :create_video %start%  2 30
        call :create_video %start%  3 20
        call :create_video %start%  6 10
        call :create_video %start% 12  5

        call :create_video %start%  4 30
        call :create_video %start%  6 20
        call :create_video %start% 12 10
        call :create_video %start% 24  5
    )

    rem start "" "%outputdir%"
exit


rem build ffmpeg commandline and call it
:create_video
    setlocal

    set input=%source%
    set start=%1
    set length=%2
    set fps=%3

    set start=%start:.00=%
    set length=%length:.00=%

    set opt=-hide_banner -y

    rem build video encoder option
    if "%ext%"=="gif"  set encodev=-loop 0
    if "%ext%"=="mp4"  set encodev=-c:v libx264 -preset slow -profile:v high -crf 25 -movflags +faststart
    if "%ext%"=="webm" set encodev=-c:v libvpx-vp9

    rem build audio encoder option
    set encodea=
    set name_a= audio
    if not "%audio%"=="true" (
        set encodea=-an
        set name_a= noaudio
    )
    if "%ext%"=="gif" set name_a=

    rem build crop filter option
    set crop_pos=%xpos%:%ypos%
    set crop_size=%width%:%height%
    set filt_crop=crop=%crop_size%:%crop_pos%

    rem build palette filter option
    set filt_palette=
    if "%ext%"=="gif" set filt_palette=,split[s0][s1];[s0]palettegen=max_colors=%colors%:reserve_transparent=0[p];[s1][p]paletteuse=dither=none:diff_mode=rectangle

    rem build fps input filter and output option (output fps option is separate from the filter fps)
    set filt_fps=
    set name_fps=
    set output_fps=
    if not "%fps%"=="0" (
        set filt_fps=fps=%fps%,
        set name_fps= fps=%fps%
        set output_fps=-r %fps%
    )

    rem build complete filter
    set filter=-vf "%filt_fps%%filt_crop%%filt_palette%"

    rem build complete output file name
    for /F "tokens=*" %%f in ("%input%") do set output=%%~nf start=%start% length=%length%%name_fps%%name_a%.%ext%

    rem build complete ffmpeg command line
    set cmd="%ffmpeg%" %opt% -ss %start% -t %length% -i "%input%" %filter% %output_fps% %encodev% %encodea% "%output%"

    >>"%log%" echo ====================================================================
    >>"%log%" echo input=%input%
    >>"%log%" echo output=%output%
    >>"%log%" echo start=%start%
    >>"%log%" echo length=%length%
    >>"%log%" echo fps=%fps%
    >>"%log%" echo cmd=%cmd%
    >>"%log%" echo.

    echo Create "%output%" (%xpos%, %ypos%, %width%, %height%) start=%start% length=%length% fps=%fps%

    %cmd% 2>>"%log%"

goto :eof
