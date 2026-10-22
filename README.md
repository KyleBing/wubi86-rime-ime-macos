# 玫枫五笔（macOS）

原生 InputMethodKit 五笔输入法，复用 iOS 版同一套 `wubi86_jidian` + librime（无 Lua，支持可分享的明暗候选栏皮肤）。

## 结构

- `MeifengWubi`：设置 / 安装 / 词库管理宿主 App
- `MeifengWubiIME`：真正的输入法进程（`LSUIElement`）
- `Shared/`：Rime 桥接、部署、用户词
- `Resources/Rime/`：内置方案

## 编译

```bash
# 需本机已装 Xcode；生成工程：
/path/to/xcodegen generate   # 或直接打开已生成的 MeifengWubi.xcodeproj

xcodebuild -project MeifengWubi.xcodeproj -scheme MeifengWubi -configuration Debug build
```

## 安装

1. 运行 `玫枫五笔.app`
2. 点「安装 / 更新输入法」
3. 系统设置 → 键盘 → 输入法 → 启用「玫枫五笔」
4. 若列表不出现，注销一次再试

也可手动把 `MeifengWubiIME.app` 拷到 `~/Library/Input Methods/`。

## 打包与发布

```bash
./scripts/package_dmg.sh   # 通用二进制 DMG，Developer ID 签名并公证
```

推 `v1.0.4` 这类标签时，`.github/workflows/release.yml` 会在 macOS runner 上打包 DMG 并发布到**本仓库**的 Releases，更新说明取自 `CHANGELOG.md` 对应版本。发版前先把版本号写进 `project.yml`（`MARKETING_VERSION`）并提交；标签与版本不一致时工作流会直接失败。

附件名固定为 `MeifengWubi-macOS.dmg`，所以说明站只用一条不变的地址：

```
https://github.com/KyleBing/wubi86-rime-ime-macos/releases/latest/download/MeifengWubi-macOS.dmg
```

仓库 Secrets 里配好 `MACOS_CERT_P12`、`MACOS_CERT_PASSWORD`、`APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID` 才会签名并公证；没配时打自签名包，其他人下载需右键打开。

注意：仓库必须是 public，未登录的人才能下载 Release 附件。私有仓库的附件只有登录且有权限的账号能取。

## 设计要点（对标鼠须管痛点）

- 候选条：`NSPanel` + `nonactivatingPanel`，不抢 key window
- Inline preedit（下划线编码）
- 切输入源通知兜底，避免 composition / 面板残留
- 不做皮肤 YAML

## 快捷操作

- 单独 Shift：中/英切换
- 数字 1–9：选词
- `date` / `time` / `week`：时间日期候选
