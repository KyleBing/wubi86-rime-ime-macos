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

## 云端同步

「设置 → 账户」登录门户账号，和码表助手、iOS、Windows 共用。默认请求地址是：

```
https://kylebing.cn/wubi/portal/
```

`https://kylebing.cn/wubi/` 是说明站，接口统一在 `/wubi/portal/` 下，旧地址不再兼容。
注册地址是 `https://kylebing.cn/wubi/manager/#/register`（管理后台 `/wubi/manager/`）。

## 打包与发布

```bash
./scripts/package_dmg.sh   # 通用二进制 DMG，Developer ID 签名并公证
```

推 `v1.1.0` 这类标签时，`.github/workflows/release.yml` 会在 macOS runner 上打包 DMG 并发布到**本仓库**的 Releases，更新说明取自 `CHANGELOG.md` 对应版本。发版前先把版本号写进 `project.yml`（`MARKETING_VERSION`）并提交；标签与版本不一致时工作流会直接失败。

Release 说明末尾会拼上 `docs/release-notes-footer.md`（「无法打开」的处理办法），`update.json` 里的 `notes` 只用 `CHANGELOG.md` 的正文，不带上这段。

附件名固定为 `MeifengWubi-macOS.dmg`，所以说明站只用一条不变的地址：

```
https://github.com/KyleBing/wubi86-rime-ime-macos/releases/latest/download/MeifengWubi-macOS.dmg
```

仓库 Secrets 里配好 `MACOS_CERT_P12`、`MACOS_CERT_PASSWORD`、`APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID` 才会签名并公证；没配时打自签名包，其他人下载需右键打开。

注意：仓库必须是 public，未登录的人才能下载 Release 附件。私有仓库的附件只有登录且有权限的账号能取。

## 程序更新

正式包用 [Sparkle 2](https://sparkle-project.org/)（SPM 依赖）。Info.plist 的 `SUFeedURL` 指向本仓库 Release 里的
`appcast.xml`，有可用更新时由 Sparkle 下载、校验、替换并重启宿主 App。

发版工作流需要两个 Secrets 才会生成 appcast：

| Secret | 用途 |
| --- | --- |
| `SPARKLE_PUBLIC_ED_KEY` | 编进 Info.plist，客户端用它验证更新包 |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA 私钥文件内容，`generate_appcast` 用它签名 |

没配时 Sparkle 不启用（`AppUpdater` 检测到公钥为空就跳过），窗口里的「程序更新」退回轻量检查：
读 `update.json`，显示版本和更新说明，再打开下载页。

两件事必须一起做，否则用户收不到更新：

- `project.yml` 里三个 target 的 `CURRENT_PROJECT_VERSION` 要同时递增。Sparkle 用构建号判断新旧，
  工作流会校验它与上一版 appcast 的关系，没涨就失败。
- 发版标签、`MARKETING_VERSION`、`CFBundleShortVersionString` 保持一致（工作流已有校验）。

生成密钥只做一次（工具随 Sparkle 的 SPM 产物下载，在
`build/DerivedDataDist/SourcePackages/artifacts/sparkle/Sparkle/bin/`）：

```bash
./generate_keys                       # 私钥存进钥匙串，并打印 SUPublicEDKey
./generate_keys -x sparkle_private    # 导出私钥文件，内容填进 SPARKLE_ED_PRIVATE_KEY
```

Sparkle 只替换 `/Applications` 里的宿主 App，`~/Library/Input Methods/MeifengWubiIME.app` 是安装时复制的副本。
宿主里的 payload 比副本新时，如果输入法进程没在运行，开窗会自动换上新组件；否则在「输入法安装」里提示，
点「安装 / 更新输入法」即可。

注意：带 Sparkle 的版本发布时，老用户装的还是不带 Sparkle 的 1.0.4，需要手动装一次；
从下一个版本开始才会自动更新。

所有安装包和更新清单都只放在本仓库的 Releases 里，不在别的服务器上托管文件。
清单里的 `download_url` 就是 `releases/latest/download/<固定附件名>`，客户端也只请求这一个地址。

## 设计要点（对标鼠须管痛点）

- 候选条：`NSPanel` + `nonactivatingPanel`，不抢 key window
- Inline preedit（下划线编码）
- 切输入源通知兜底，避免 composition / 面板残留
- 不做皮肤 YAML

## 快捷操作

- 单独 Shift：中/英切换
- 数字 1–9：选词
- `date` / `time` / `week`：时间日期候选
