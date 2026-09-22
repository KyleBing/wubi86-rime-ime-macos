# 玫枫五笔（macOS）

原生 InputMethodKit 五笔输入法，复用 iOS 版同一套 `wubi86_jidian` + librime（无 Lua、无皮肤配置）。

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

1. 运行 `MeifengWubi.app`
2. 点「安装 / 更新输入法」
3. 系统设置 → 键盘 → 输入法 → 启用「玫枫五笔」
4. 若列表不出现，注销一次再试

也可手动把 `MeifengWubiIME.app` 拷到 `~/Library/Input Methods/`。

## 设计要点（对标鼠须管痛点）

- 候选条：`NSPanel` + `nonactivatingPanel`，不抢 key window
- Inline preedit（下划线编码）
- 切输入源通知兜底，避免 composition / 面板残留
- 不做皮肤 YAML

## 快捷操作

- 单独 Shift：中/英切换
- 数字 1–9：选词
- `date` / `time` / `dt` / `ts`：时间日期候选
