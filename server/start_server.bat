@echo off
rem FlowMoney AI server launcher (ASCII only: cmd parses batch by ANSI codepage)
cd /d "%~dp0"

if not exist .env (
    echo [ERROR] .env not found. Copy .env.example to .env and set DASHSCOPE_API_KEY
    pause
    exit /b 1
)

python -c "import dashscope, fastapi, uvicorn" 2>nul || (
    echo [SETUP] installing dependencies...
    pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/
)

echo [START] AI backend on http://YOUR_LAN_IP:8765  (Ctrl+C to stop)
python main.py
pause
