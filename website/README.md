# Cruft Product Site

Cruft 的静态产品介绍站，使用 Vite 构建并通过 Cloudflare Workers Static Assets 部署到
`cruft.phpz.org`。视觉系统与 `LinguaDock/website`、`wordclip/website` 同源（同一套
token、同一套页面节奏），三个站看起来是一家人。

```bash
pnpm install
pnpm dev
```

构建与本地预览：

```bash
pnpm build
pnpm preview
```

完成 Cloudflare 登录后部署：

```bash
pnpm run deploy
```

> `pnpm deploy` 是 pnpm 自己的内置命令（把工作区包部署到一个目录），会直接报
> `ERR_PNPM_INVALID_DEPLOY_TARGET`。必须写 `pnpm run deploy` 才会跑 package.json 里的脚本。

## 站点只介绍产品

**不要在站上出现技术信息。** 不放构建步骤、命令、路径、依赖名和实现细节（SwiftUI、
SwiftData、GRDB、ECDICT、SM-2、Vision、Keychain、`~/Library/...` 这类一律不出现）。
产品范围内的名字可以留——Cruft 说清它清哪些工具链、LinguaDock 说清它接哪种模型服务，
那是用户要知道的东西，不是实现细节。

**wordclip 是私有 repo**，它的站上不能出现任何 `github.com/dofy/wordclip` 链接或
「开源 / MIT」字样——对访客是 404。Cruft 和 LinguaDock 是公开的，页头页脚的 GitHub
与 issue 链接保留，当反馈渠道。

三个站都没有 release，所以页尾是一个「即将推出」状态区（`.release`），不是下载按钮。
真的有下载之后再换成按钮。

## 三语页面

每种语言一个独立静态页，而不是运行时切文案——营销页要让搜索引擎分别收录。

| 路径 | 语言 | 文件 |
|------|------|------|
| `/` | English（也是 `hreflang="x-default"`） | `index.html` |
| `/zh-Hans/` | 简体中文 | `zh-Hans/index.html` |
| `/zh-Hant/` | 繁體中文（台湾用词） | `zh-Hant/index.html` |

三页共用 `styles.css` 和 `main.js`（资源路径都是绝对的 `/...`，所以从子目录也能取到）。

改动时注意：

- **新增页面必须同时加进 `vite.config.js` 的 `build.rollupOptions.input`。** Vite 只打包列出来的
  HTML 入口，漏了就会静默地不出现在 `dist/`。
- 三页的 `<link rel="alternate" hreflang>` 是互指的，加语言要三页一起改。
- 页头的 `.lang-switch` 是 `<nav>`；`styles.css` 在 ≤960px 把 `nav` 藏起来，所以那条媒体查询里
  单独把 `.lang-switch` 显示回来。加新的页头元素时别踩这个。
- `main.js` 只在 `/` 上做一次 `navigator.language` 跳转，并且用 `localStorage` 记住用户点过的
  语言——手动选过之后不再自动跳。语言页自己不跳转，否则会和切换器打架。
- `styles.css` 是从 `LinguaDock/website/styles.css` 派生的：token、页头、区块节奏、按钮、
  `.workflow-rail`、`.details`、深色 `.privacy` 面板、`.start`/`.terminal`、页脚和两条媒体查询
  都逐字保留，只把 hero 里 LinguaDock 专属的「原文窗 → 快捷键 → 译文卡」换成本站的
  「任务清单卡 → 释放空间卡」。LinguaDock 的 `.model-*` 系列在这里改名成 `.duo-*`。
  **改共享部分时三个站一起改**，否则风格会慢慢漂开。
- `.traffic-lights` 和 `.terminal-bar` 的圆点是**同一条规则**。改 hero 的 mock 时别顺手把它
  删了，否则安装命令那个终端卡的圆点会一起没。
- hero 里的数字（8.4 GB / 13.3 GB / 238 GB）是示意值，不是真实测量结果。
- 三个站**只共享视觉系统**（token、页头、区块节奏、按钮、深色面板、页脚、媒体查询），
  区块结构不必一致，各站按自己的产品来排。
- `public/app-icon.png` 是从 `Sources/Assets.xcassets/AppIcon.appiconset/icon_512.png`
  拷来的。换图标时记得同步。
