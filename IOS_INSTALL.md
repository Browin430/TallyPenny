# iOS 内测安装指南（Windows + 免费 Apple ID）

iOS 的 IPA 只能在 macOS 上编译。本项目 Windows 上的做法：
**GitHub Actions 云端出未签名 IPA → Windows 用 Sideloadly + 你的 Apple ID 重签 → USB 装机**。
免费签名 **7 天过期**，过期前重签一次即可（数据不丢）。

## 一、一次性准备（约 15 分钟）

1. **推送代码到 GitHub 私有仓库**（无远程仓库时）：
   ```bash
   git remote add origin https://github.com/<你的用户名>/flowmoney.git
   git push -u origin main
   ```
   仓库保持 Private 即可；`server/app_build_env.json` 已被 gitignore，不会上传。

2. **配置 token Secret**（跳过 = iOS 包里账单导入 401）：
   GitHub 仓库页 → Settings → Secrets and variables → Actions →
   New repository secret，名称 `FM_API_TOKEN`，值取自本地 `server/app_build_env.json`。

3. **Windows 装两个 Apple 官方软件**（Sideloadly 依赖它们的 USB 驱动，
   **不要装 Microsoft Store 版**，去 apple.com/cn 下载）：
   - iTunes（64 位，apple.com 版）
   - iCloud（apple.com 版）
   - 然后装 [Sideloadly](https://sideloadly.io)

## 二、每次出包（约 20 分钟，全自动）

1. `git push` 最新代码。
2. GitHub 仓库 → **Actions** 标签 → 左侧 `build-ios-unsigned` → **Run workflow**。
3. 跑完后进入该次运行页面底部 **Artifacts**，下载 `flowmoney-ios-unsigned`，解压得到 `.ipa`。

## 三、装机（每台手机约 5 分钟）

1. iPhone 用数据线连电脑，解锁手机，弹窗选「信任」。
2. 打开 Sideloadly：拖入 `.ipa` → 填你的 Apple ID 和密码
   （开了两步验证的账号：先到 appleid.apple.com → 登录与安全 → 生成「App 专用密码」）。
3. 点 **Start**，等待手机上出现图标。
4. iPhone：**设置 → 通用 → VPN与设备管理** → 点你的 Apple ID（开发者 App）→ **信任**。
5. 若提示 bundle id 被占用：在 Sideloadly 勾选 change bundle id（自动加后缀）后重试。

## 四、7 天续期

签名过期前，重做「三、装机」同一操作（同一 Apple ID + 同一 IPA）。
同 bundle id 覆盖安装，**App 数据保留**。
免费 Apple ID 限制：同一设备最多 3 个自签 App；每周最多注册 10 个 App ID。

## 已知差异与注意

- 最低 iOS 15.0。
- Info.plist 已含麦克风 / 相机 / 相册权限声明（缺了会闪退，勿删）。
- 免费签名只是权宜方案；要长期用或上架，开 ¥688/年 开发者账号走 TestFlight。
