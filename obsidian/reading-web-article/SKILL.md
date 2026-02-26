# Obsidian 阅读区 - 网页文章处理

## 触发条件
当 Buck 说出以下关键词时触发此 skill：
- "阅读 [url] 写入 obsidian 阅读区"
- "阅读 [url] 写入 obsidian"
- "处理文章 [url] 到 obsidian"

## Obsidian 阅读区位置
- **根目录**：`~/Dropbox/ObsidianLibrary/OpenClaw/`
- **阅读区**：`~/Dropbox/ObsidianLibrary/OpenClaw/reading/`
- **README**：`~/Dropbox/ObsidianLibrary/OpenClaw/README.md`

## 工作流程

### 1. 预处理
1. **读取 README 确认规则**：
   - 执行前先读 `~/Dropbox/ObsidianLibrary/OpenClaw/README.md`
   - 确认当前阅读区规则是否有变化
   - 如果发现新平台/新规则，可在处理完成后回填到 README

2. **URL 规范化**：
   - 分析 URL 结构，识别核心参数：
     - **X (x.com / twitter.com)**：保留 `/status/<id>`，去掉 `?s=20` 等追踪参数
     - **Medium**：保留 `/@author/slug` 或 `/p/<id>`，去掉 `?source=...` 等
     - **其他平台**：保留文章标识符（path/id），去掉广告追踪、来源、分享参数
   - 规范化后的 URL 用于后续查重和存储
   - **示例**：
     ```
     原始：https://x.com/user/status/123456?s=20&t=abc
     规范：https://x.com/user/status/123456
     ```

3. **查重检测**：
   - 在目标目录 `reading/<domain>/` 下搜索所有 `.md` 文件
   - 使用 `grep -l "^url: "` 提取所有文件的 frontmatter URL
   - 比对规范化后的 URL：
     - 如果**完全匹配**：告知 Buck "该文章已处理：`<文件路径>`"，**终止执行**
     - 如果未匹配：继续处理
   - **注意**：URL 比对前也需要规范化（移除参数后比较）

4. **解析 URL**：
   - 提取域名（如 `x.com`、`medium.com`、`example.org`）
   - 确定目标目录：`reading/<domain>/`
   - 如果目录不存在，自动创建

### 2. 抓取文章（直接使用 headless 浏览器）
1. **启动浏览器**（如未运行）：
   - `browser(action=start, profile=openclaw)`

2. **导航到目标 URL**：
   - `browser(action=navigate, targetUrl=<url>)`
   - 或 `browser(action=open, targetUrl=<url>)` 打开新标签页

3. **抓取页面内容**：
   - `browser(action=snapshot, snapshotFormat=ai)`
   - 提取文章主体：标题、作者、正文、图片链接

4. **提取图片 URL**：
   - 从 snapshot 中识别文章内嵌图片的实际 URL
   - 优先使用完整的 `https://` 链接（如 `pbs.twimg.com`、直接图片 URL 等）
   - 如果只有相对路径（如 X 的 `/media/...`），尝试拼接为完整 URL
   - **无法获取真实 URL 时**：
     - 移除图片占位符
     - 保留图片说明文字（如果有），转为粗体或正文强调
     - 不要留下无效的 `![...]` 引用

5. **抓取失败时**：
   - 如果遇到订阅墙/登录墙/内容无法提取：**不处理**
   - 直接告知 Buck："该文章需要订阅/登录，建议换其他方式处理"
   - 不要尝试绕过/猜测

### 3. 生成内容

#### 3.1 判断语言
- 识别文章主要语言（中文 / 其他）

#### 3.2 内容结构

**如果是中文文章**：
```markdown
# <文章标题>

---

## 要点总结

<AI 提炼的重要信息>
```

**如果是非中文文章**：
```markdown
# <文章标题>（<作者>）

---

## 一、要点总结

<AI 总结>

---

## 二、原文中文翻译（尽量保持原结构）

<全文翻译，保持原文段落/小节结构>
```

**特殊情况：速查表/参考文档**：
- 如果文章是速查表、命令参考、API 文档等工具性内容
- **不做总结**，直接翻译内容（保持原结构：命令/参数/说明）
- 用户可能明确要求"不用总结"或"简单翻译用法"

#### 3.3 Frontmatter
固定字段（所有文章必填）：
```yaml
---
managed_by: openclaw
created_at: YYYY-MM-DD HH:MM:SS
updated_at: YYYY-MM-DD HH:MM:SS
url: <原文链接>
platform: <域名>
tags:
  - Reading/<Platform>
  - <根据内容提取的分类标签>
author: <作者名>  # 能提取则提取，不能则留空或省略此行
---
```

**注意**：
- `created_at` / `updated_at` 使用执行时的当前时间（Berlin 时区）
- `platform` 为域名（如 `x.com`、`medium.com`）
- `tags` 至少包含 `Reading/<Platform>`（首字母大写），其余根据文章内容提取 1-3 个相关标签
- `author` 尽量从文章元数据/正文提取，提取不到则留空

### 4. 文件命名

#### 4.1 Slug 生成规则
1. **优先使用文章标题**：
   - 如果标题简短清晰（≤ 60 字符），转换为 slug：
     - 转小写
     - 空格/特殊字符转 `-`
     - 去掉连续的 `-`
     - 移除首尾 `-`

2. **标题过长时**：
   - 根据文章主题编写简短 slug（30-60 字符）
   - 保持语义清晰、易识别

#### 4.2 完整文件名
格式：`YYYY-MM-DD-<slug>.md`

示例：
- `2026-02-19-something-big-is-happening-ai-transition-warning.md`
- `2026-02-20-openai-releases-gpt-5.md`
- `2026-02-20-rust-memory-safety-guide.md`

#### 4.3 冲突处理
- 如果文件名已存在，在 slug 后加 `-2`、`-3` 递增
- 或询问 Buck 是否覆盖/重命名

### 5. 写入文件
1. 拼接完整路径：`~/Dropbox/ObsidianLibrary/OpenClaw/reading/<domain>/YYYY-MM-DD-<slug>.md`
2. 确保目录存在（`mkdir -p`）
3. 写入内容
4. 报告完成：告知 Buck 文件位置、字数、是否成功

### 6. README 回填（可选）
如果处理了新平台（之前 README 未提及）：
1. 在 `~/Dropbox/ObsidianLibrary/OpenClaw/README.md` 中补充说明
2. 更新"阅读区"章节，列出新平台目录
3. 告知 Buck 已回填

## 示例执行

### 输入
```
阅读 https://x.com/mattshumer_/status/2021256989876109403 写入 obsidian
```

### 执行步骤
1. 读取 `README.md` 确认规则 ✓
2. 解析 URL → 域名 `x.com`
3. web_fetch 抓取文章
4. 识别语言：英文
5. 生成要点总结 + 全文翻译
6. 提取 tags：`Reading/X`, `AI/趋势`, `AI/转型`
7. 生成 slug：`something-big-is-happening-ai-transition-warning`
8. 写入：`~/Dropbox/ObsidianLibrary/OpenClaw/reading/x.com/2026-02-19-something-big-is-happening-ai-transition-warning.md`
9. 报告完成

## 注意事项
1. **不处理订阅/登录内容**：遇到抓取失败直接告知，不要尝试绕过
2. **保持原文结构**：翻译时尽量保持段落、小节、引用等原始结构
3. **tags 精炼**：不要过度标注，1-3 个核心标签即可
4. **时间准确**：frontmatter 中的时间使用执行时的 Berlin 时区时间
5. **README 协作**：新平台出现时主动回填，保持文档同步

## 相关文件
- Obsidian 根 README：`~/Dropbox/ObsidianLibrary/OpenClaw/README.md`
- 阅读区根目录：`~/Dropbox/ObsidianLibrary/OpenClaw/reading/`
- 技能记忆：记录在 `MEMORY.md` 中的触发约定
