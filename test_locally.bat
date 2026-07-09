@echo off
echo === Building Unified Local Test Environment ===

echo [1/3] Building Flutter App...
call flutter build web --wasm --base-href "/recite/"
if %errorlevel% neq 0 exit /b %errorlevel%

echo [2/3] Injecting Flutter App into React Public Folder...
xcopy /E /I /Y "build\web" "landing_page\public\recite"

echo [3/3] Building React Landing Page...
cd landing_page
call npm run build
if %errorlevel% neq 0 exit /b %errorlevel%

echo === Build Complete! Starting Local Server ===
echo Testing on http://localhost:3000
echo Press Ctrl+C to stop.
call npx vite preview
pause
