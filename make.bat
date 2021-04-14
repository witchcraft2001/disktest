rem echo OFF
echo Assembling ...
C:\asm\sjasm\sjasmplus.exe --lst=disktest.lst --lstlab disktest.asm
if errorlevel 1 goto ERR
goto SUCCESS
:ERR
rem pause
echo Some Building ERRORs!!!
rem exit
goto END
:SUCCESS
echo Done!
:END
pause 0