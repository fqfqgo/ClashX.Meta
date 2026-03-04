# CI 排查说明（GitHub Actions 下 project damaged / JSON parse error）

## 1. 检查 Git 冲突标记

在项目根目录运行：

```bash
grep -r "<<<<<<<" .
# 或针对 xcodeproj
grep -rE "<<<<<<<|=======|>>>>>>>" ClashX.xcodeproj/
```

若发现冲突：打开 `ClashX.xcodeproj/project.pbxproj` 解决冲突，或回滚该文件：

```bash
git checkout ClashX.xcodeproj/project.pbxproj
```

**Workflow 已做**：步骤 `check no conflict markers in project` 会在 CI 中执行上述检查，发现冲突则直接失败并报错。

---

## 2. 检查 CI 脚本中的“修改”步骤

- **build infos**：仅修改 `ClashX/Info.plist`（版本号、git 信息等），**不修改** `.xcodeproj` / `project.pbxproj`。
- 无 `sed` / `echo >` 写入 `project.pbxproj` 或 `*.xcodeproj` 内文件。
- 无向 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 写回 project 的步骤。

若变量为空，PlistBuddy 会写空字符串到 Info.plist，不会影响 xcodeproj。

---

## 3. 校验项目文件格式

`project.pbxproj` 首行是 `// !$*UTF8*$!`（OpenStep plist 格式），`plutil -lint` 会报 `Unexpected character / at line 1`，故 **不能用 plutil 校验此文件**。若需检查格式，只能在 Xcode 中打开工程或依赖 xcodebuild 报错信息。

---

## 4. 子模块 (Submodules)

`actions/checkout` 已设置 `submodules: recursive`，子模块会一并拉取。当前仓库无 `.gitmodules`，此项仅为预留。
