@echo off
set found=no
for /f %%i in ('dir /b') do (
    if "%%~ni"=="ruby_lib" set found=yes
)
if %found%=="yes" (
    echo ruby_lib found in the temp folder which is interfering with the install script... would you like to delete it?
    set /p answer="Delete (y/N)?: "
    set delete=no
    if /i "%answer%" EQU "y" (
        set delete=yes
    )
    if "%delete%"=="no" (
        echo ruby_lib folder must be deleted in from the temp folder for the script for proceed
    ) else (
        rmdir /s /q "ruby_lib"
    )
) else (
    git clone https://github.com/EinarsNG/ruby_lib.git
    cd ruby_lib

    set rubocop=no
    for /f %%i in ('gem list --no-version') do (
        if "%%i"=="rubocop" (
            set rubocop=yes
        )
    )

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
