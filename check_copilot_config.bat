@echo off
REM GitHub Copilot 配置验证脚本 (Windows 版本)
REM 检查所有必要的文件是否正确创建

echo.
echo ================================
echo GitHub Copilot 配置验证
echo ================================
echo.

set "error_count=0"

REM 检查目录
echo 检查目录结构...
if exist ".github\" (
    echo [√] 目录存在: .github\
) else (
    echo [×] 目录缺失: .github\
    set /a error_count+=1
)

if exist ".github\prompts\" (
    echo [√] 目录存在: .github\prompts\
) else (
    echo [×] 目录缺失: .github\prompts\
    set /a error_count+=1
)

if exist ".vscode\" (
    echo [√] 目录存在: .vscode\
) else (
    echo [×] 目录缺失: .vscode\
    set /a error_count+=1
)

echo.
echo 检查配置文件...

REM 检查主要配置文件
if exist ".github\copilot-instructions.md" (
    echo [√] 文件存在: .github\copilot-instructions.md
) else (
    echo [×] 文件缺失: .github\copilot-instructions.md
    set /a error_count+=1
)

if exist ".vscode\settings.json" (
    echo [√] 文件存在: .vscode\settings.json
) else (
    echo [×] 文件缺失: .vscode\settings.json
    set /a error_count+=1
)

if exist "COPILOT_SETUP.md" (
    echo [√] 文件存在: COPILOT_SETUP.md
) else (
    echo [×] 文件缺失: COPILOT_SETUP.md
    set /a error_count+=1
)

echo.
echo 检查提示文件...

REM 提示文件列表
set "prompts=Add Network Module.prompt.md Configuration Template.prompt.md Documentation Generator.prompt.md Network Troubleshooting.prompt.md Quick Start Guide.prompt.md Security Review.prompt.md Shell Script Optimization.prompt.md"

for %%p in (%prompts%) do (
    if exist ".github\prompts\%%p" (
        echo [√] 提示文件: %%p
    ) else (
        echo [×] 提示文件缺失: %%p
        set /a error_count+=1
    )
)

echo.
echo ================================
if %error_count%==0 (
    echo 配置验证完成！所有文件都已正确创建。
    echo.
    echo 下一步：
    echo 1. 重启 VS Code
    echo 2. 查看 COPILOT_TESTING.md 了解测试方法
    echo 3. 开始使用新的 Copilot 配置
) else (
    echo 发现 %error_count% 个问题，请检查上述缺失的文件。
)
echo ================================
echo.

pause
