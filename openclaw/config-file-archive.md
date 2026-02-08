# config-file-archive.sh

清理 OpenClaw 配置目录（`~/.openclaw`）中的备份文件，将其归档到 `.archived/` 子目录并按时间戳重命名。

## 功能

- 扫描 `openclaw.json.bak*` 备份文件
- 提取文件创建时间（macOS birth time）
- 重命名为 `openclaw.bak.YYYYMMDD-HHMMSS.json` 格式
- 移动到 `.archived/` 目录
- 如果 `.archived/` 不存在则自动创建

## 用法

```bash
./skills/openclaw/config-file-archive.sh
```

无需参数，直接运行即可。脚本会自动处理 `$HOME/.openclaw` 目录。

## 输出示例

```
Move backup config file: openclaw.json.bak => .archived/openclaw.bak.20260208-142248.json
Move backup config file: openclaw.json.bak.1 => .archived/openclaw.bak.20260208-142240.json
```

## 错误处理

- 如果 `~/.openclaw` 目录不存在，脚本会报错退出
- 使用 `set -euo pipefail` 确保任何错误都会中止执行

## 技术细节

- **Shell:** zsh，shebang: `#!/usr/bin/env zsh`
- **时间格式:** `%Y%m%d-%H%M%S`
- **时间来源:** macOS `stat -f '%SB'`（birth time）
- **Glob:** 使用 zsh `(N)` qualifier 安全处理无匹配情况
