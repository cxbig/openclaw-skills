# Skills - 工具集目录

自定义脚本和工具集，按用途分类存放。

## 目录结构

### openclaw/
OpenClaw 运维工具集。

**Scripts:**
- `config-file-archive.sh` - 清理并归档配置备份文件（`openclaw.json.bak*`）

---

## 约定

- **Shell:** 优先使用 zsh（macOS 默认），shebang 使用 `#!/usr/bin/env zsh`（可移植性）
- **时间格式:** 统一使用 `YYYYMMDD-HHMMSS`（符合 OpenClaw 归档约定）
- **目录结构:** 按用途分类（如 `openclaw/`、`data/`、`utils/` 等）
- **文档:** 每个脚本可附带同名 `.md` 文件说明细节
