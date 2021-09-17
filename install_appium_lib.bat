@echo off
@REM set found=no
@REM for /f %%i in ('dir /b') do (
@REM     if "%%~ni"=="ruby_lib" set found=yes
@REM )
@REM if %found%=="yes" (
@REM     echo ruby_lib found in the temp folder which is interfering with the install script... would you like to delete it?
@REM     set /p answer="Delete (y/N)?: "
@REM     set delete=no
@REM     if /i "%answer%" EQU "y" (
@REM         set delete=yes
@REM     )
@REM     if "%delete%"=="no" (
@REM         echo ruby_lib folder must be deleted in from the temp folder for the script for proceed
@REM     ) else (
@REM         rmdir /s /q "ruby_lib"
@REM     )
@REM ) else (
@REM     git clone https://github.com/EinarsNG/ruby_lib.git
@REM     cd ruby_lib

@REM     set rubocop=no
@REM     for /f %%i in ('gem list --no-version') do (
@REM         if "%%i"=="rubocop" (
@REM             set rubocop=yes
@REM         )
@REM     )

@REM     if %rubocop%=="no" (
@REM         echo Rubocop is missing... installing
@REM         gem install rubocop
@REM     )
@REM     rake install
@REM     cd ..
@REM     rmdir /s /q "ruby_lib"
@REM )
git clone https://github.com/EinarsNG/ruby_lib.git
cd ruby_lib
rake install
cd ..
rmdir /s /q "ruby_lib"
