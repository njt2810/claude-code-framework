@echo off
setlocal enabledelayedexpansion

echo.
echo ===================================================
echo   Installing Claude Code Development Framework
echo ===================================================
echo.

set "CLAUDE_HOME=%USERPROFILE%\.claude"

echo [1/9] Creating directory structure...
if not exist "%CLAUDE_HOME%\skills" mkdir "%CLAUDE_HOME%\skills"
if not exist "%CLAUDE_HOME%\agents" mkdir "%CLAUDE_HOME%\agents"
if not exist "%CLAUDE_HOME%\rules" mkdir "%CLAUDE_HOME%\rules"
if not exist "%CLAUDE_HOME%\hooks\scripts" mkdir "%CLAUDE_HOME%\hooks\scripts"
if not exist "%CLAUDE_HOME%\scripts" mkdir "%CLAUDE_HOME%\scripts"
if not exist "%CLAUDE_HOME%\logs" mkdir "%CLAUDE_HOME%\logs"
if not exist "%CLAUDE_HOME%\templates\wiki\decisions" mkdir "%CLAUDE_HOME%\templates\wiki\decisions"
if not exist "%CLAUDE_HOME%\templates\wiki\runbooks" mkdir "%CLAUDE_HOME%\templates\wiki\runbooks"
if not exist "%CLAUDE_HOME%\templates\wiki\logs" mkdir "%CLAUDE_HOME%\templates\wiki\logs"
if not exist "%CLAUDE_HOME%\templates\rules" mkdir "%CLAUDE_HOME%\templates\rules"
if not exist "%CLAUDE_HOME%\templates\ci" mkdir "%CLAUDE_HOME%\templates\ci"
echo    Done.

echo [2/9] Installing skills (slash commands)...
for %%S in (init-project new-feature bug-fix wrap-up resume learn help document-all evaluate-repo status security-check constitution review-drift knowledge production-audit review-ui framework-check curate lock-skill unlock-skill pin-skill unpin-skill) do (
    if not exist "%CLAUDE_HOME%\skills\%%S" mkdir "%CLAUDE_HOME%\skills\%%S"
    copy /Y "skills\%%S\SKILL.md" "%CLAUDE_HOME%\skills\%%S\SKILL.md" >nul 2>&1
)
echo    22 skills installed.

echo [3/9] Installing agents...
copy /Y "agents\*.md" "%CLAUDE_HOME%\agents\" >nul 2>&1
echo    6 agents installed (5 always-on + 1 on-demand).

echo [4/9] Installing rules...
copy /Y "rules\*.md" "%CLAUDE_HOME%\rules\" >nul 2>&1
echo    5 global rules installed.

echo [5/9] Installing hooks...
copy /Y "hooks\scripts\*.sh" "%CLAUDE_HOME%\hooks\scripts\" >nul 2>&1
copy /Y "settings.json" "%CLAUDE_HOME%\settings.json" >nul 2>&1
echo    12 hooks and settings installed.

echo [6/9] Installing utility scripts...
copy /Y "hooks\scripts\timed-run.sh" "%CLAUDE_HOME%\scripts\timed-run.sh" >nul 2>&1
echo    Utility scripts installed.

echo [7/9] Installing telemetry log...
if not exist "%CLAUDE_HOME%\logs\skill-usage.log" type nul > "%CLAUDE_HOME%\logs\skill-usage.log"
echo    Telemetry log ready.

echo [8/9] Installing templates...
copy /Y "templates\wiki\*.md" "%CLAUDE_HOME%\templates\wiki\" >nul 2>&1
copy /Y "templates\wiki\decisions\*.md" "%CLAUDE_HOME%\templates\wiki\decisions\" >nul 2>&1
copy /Y "templates\wiki\runbooks\*.md" "%CLAUDE_HOME%\templates\wiki\runbooks\" >nul 2>&1
copy /Y "templates\rules\*.md" "%CLAUDE_HOME%\templates\rules\" >nul 2>&1
copy /Y "templates\ci\*.yml" "%CLAUDE_HOME%\templates\ci\" >nul 2>&1
echo    Templates installed.

echo [9/9] Installing global CLAUDE.md and TEAM.md...
if exist "%CLAUDE_HOME%\CLAUDE.md" (
    echo    CLAUDE.md already exists - backing up to CLAUDE.md.backup
    copy /Y "%CLAUDE_HOME%\CLAUDE.md" "%CLAUDE_HOME%\CLAUDE.md.backup" >nul 2>&1
)
copy /Y "CLAUDE.md" "%CLAUDE_HOME%\CLAUDE.md" >nul 2>&1
copy /Y "TEAM.md" "%CLAUDE_HOME%\TEAM.md" >nul 2>&1
echo    Done.

echo.
echo ===================================================
echo   Verifying installation...
echo ===================================================
echo.

set "ERRORS=0"

if exist "%CLAUDE_HOME%\CLAUDE.md" (
    echo    OK: CLAUDE.md
) else (
    echo    MISSING: CLAUDE.md
    set /a ERRORS+=1
)

if exist "%CLAUDE_HOME%\TEAM.md" (
    echo    OK: TEAM.md
) else (
    echo    MISSING: TEAM.md
    set /a ERRORS+=1
)

if exist "%CLAUDE_HOME%\settings.json" (
    echo    OK: settings.json
) else (
    echo    MISSING: settings.json
    set /a ERRORS+=1
)

if exist "%CLAUDE_HOME%\agents\code-reviewer.md" (
    echo    OK: 6 agents
) else (
    echo    MISSING: agents
    set /a ERRORS+=1
)

if exist "%CLAUDE_HOME%\hooks\scripts\verify-before-stop.sh" (
    echo    OK: hooks
) else (
    echo    MISSING: hooks
    set /a ERRORS+=1
)

if exist "%CLAUDE_HOME%\skills\init-project\SKILL.md" (
    echo    OK: 22 skills
) else (
    echo    MISSING: skills
    set /a ERRORS+=1
)

echo.
echo   Checking dependencies...
where bash >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo    WARNING: bash not found. Hooks require Git Bash.
    echo    Install Git for Windows: https://git-scm.com/download/win
) else (
    echo    OK: bash available
)

where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo    WARNING: git not found. Install Git for Windows.
) else (
    echo    OK: git available
)

echo.
if !ERRORS! EQU 0 (
    echo ===================================================
    echo   Installation complete!
    echo ===================================================
) else (
    echo ===================================================
    echo   Installation finished with !ERRORS! warnings
    echo ===================================================
)

echo.
echo   Location: %CLAUDE_HOME%
echo.
echo   Installed:
echo     22 skills   - /init-project /new-feature /bug-fix
echo                   /wrap-up /resume /learn /help
echo                   /document-all /evaluate-repo /status
echo                   /security-check /constitution
echo                   /review-drift /knowledge
echo                   /production-audit /review-ui
echo                   /framework-check /curate
echo                   /lock-skill /unlock-skill
echo                   /pin-skill /unpin-skill
echo     6 agents    - code-reviewer test-engineer
echo                   wiki-updater security-auditor
echo                   knowledge-agent ui-ux-engineer
echo     5 rules     - security capability-gaps skill-evolution
echo                   config-protection fact-forcing
echo     12 hooks    - session-start bash-guard pre-compact
echo                   verify-before-stop session-monitor
echo                   session-summary loop-detector
echo                   session-logger statusline
echo                   skill-telemetry idle-detection
echo                   session-end
echo     Templates   - wiki CI/CD rules
echo.
echo   To use: open any project folder in Claude Code and type:
echo     /init-project personal
echo     /init-project omasu
echo     /init-project xtend
echo     /init-project learning
echo.
echo   Type /help inside Claude Code to see all commands.
echo ===================================================
echo.

endlocal
