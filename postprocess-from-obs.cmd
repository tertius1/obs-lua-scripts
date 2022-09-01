@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
REM postprocess-from-obs.cmd -- video postprocessing called by OBS

REM --------------------------------------------------------
REM If your ffmpeg isn't in the PATH, remove the REM from the
REM second SET ffmpeg=... line and change the path accordingly.
SET ffmpeg=ffmpeg.exe
REM SET ffmpeg=C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe
REM --------------------------------------------------------
REM If you want a logfile lf ffmpeg processing, activate it here
SET log=nul
REM SET log=ffmpeg.log
REM --------------------------------------------------------

    if "%~1"=="" goto :help
    if "%~1"=="process" goto :process

    REM read command line
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

    REM log calls
    >>"%destdir%\%~n0.log" echo %*

    md "%outputdir%" 1>nul 2>nul
    if not exist "%outputdir%" (
        echo Unable to create output directory "%outputdir%"
        goto :help
    )

    set again=%outputdir%\process_again.cmd

    REM create process_again.cmd in outputdir for manual direct postprocessing
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
    echo postprocess-from-obs.cmd -- video postprocessing called by OBS
    echo.
    echo Usage:
    echo   postprocess_from_obs.cmd ^<video file^> ^<destdir^> ^<xpos^> ^<ypos^> ^<width^> ^<height^> ^<start^> ^<length^> ^<fps^> ^<video type^> ^<gif colors^> ^<variated length^> ^<audio^>
    echo.
    pause
goto :eof


REM Do actual processing. Configuration is from environment variables.
:process

    if "%outputdir%"=="" (
        echo Error: no outputdir given
        goto :help
    )

    cd /d "%outputdir%"

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

    REM gif exactly according to given values
    call :create_video %start% %length% %fps%

    if "%variated%"=="true" (

        REM some fps variants
        REM  ----------------------------------
        call :create_video %start% %length% 5
        call :create_video %start% %length% 10
        call :create_video %start% %length% 20
        call :create_video %start% %length% 30

        REM some more variants
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

    REM start "" "%outputdir%"
exit


REM build ffmpeg commandline and call it
:create_video
    setlocal

    set input=%source%
    set start=%1
    set length=%2
    set fps=%3

    set start=%start:.00=%
    set length=%length:.00=%

    set opt=-hide_banner -y

    REM build video encoder option
    if "%ext%"=="gif"  set encodev=-loop 0
    if "%ext%"=="mp4"  set encodev=-c:v libx264 -preset slow -profile:v high -crf 25 -movflags +faststart
    if "%ext%"=="webm" set encodev=-c:v libvpx-vp9

    REM build audio encoder option
    if not "%audio%"=="true" (
        set encodea=-an
        set name_a= noaudio
    )
    if "%ext%"=="gif" set name_a=

    REM build crop filter option
    set filt_crop=crop=%width%:%height%:%xpos%:%ypos%

    REM build palette filter option for gif images
    REM "dither=none" will produce slight color distortion but avoid dithering pixelation.
    REM Use "dither=sierra2_4a" for standard ffmpeg dithering.
    if "%ext%"=="gif" set filt_palette=,split[s0][s1];[s0]palettegen=max_colors=%colors%:reserve_transparent=0[p];[s1][p]paletteuse=dither=none:diff_mode=rectangle

    REM build fps input filter option
    REM don't ask me why setpts=PTS-1 makes the fps filter not produce stutter
    if not "%fps%"=="0" (
        set filt_fps=,setpts=PTS-1,fps=%fps%:round=down
        set name_fps= fps=%fps%
    )
    REM for debugging, enable drawing of frame number and frame time
    REM set filt_text=,drawtext=text=%%{n} %%{pts}:fontsize=12:x=(w-tw)/2: y=h-(2*lh):fontcolor=white:box=1:boxcolor=0x00000099

    REM build complete filter
    set filter=-vf "%filt_crop%%filt_text%%filt_fps%%filt_palette%"

    REM build complete output file name
    for /F "tokens=*" %%f in ("%input%") do set output=%%~nf start=%start% length=%length%%name_fps%%name_a%.%ext%

    REM build complete ffmpeg command line
    set cmd="%ffmpeg%" %opt% -ss %start% -t %length% -i "%input%" %filter% %encodev% %encodea% "%output%"

    >>"%log%" echo ==============================================================================
    >>"%log%" echo.
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
