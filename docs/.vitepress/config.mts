import { writeFileSync } from 'node:fs'
import { defineConfig } from 'vitepress'
import { configureDiagramsPlugin, createBuildTimeDiagramsPlugin } from 'vitepress-plugin-diagrams'

const remoteLogoUrl = 'https://raw.githubusercontent.com/crazydan-studio/kun-shell/refs/heads/master/logo.svg'
let logo = remoteLogoUrl
let fetchLogo = async (distDir: string) => {}

const vitePlugins = []
const diagramsPluginOpts = {
  diagramsDir: 'public/diagrams',
  publicPath: '/diagrams',
}
let configMarkdown = (md) => {
  configureDiagramsPlugin(md, diagramsPluginOpts)
}

if (process.env.NODE_ENV == 'production') {
  logo = '/logo.svg'
  fetchLogo = async (distDir: string) => {
    const distLogFile = distDir + logo

    await fetch(remoteLogoUrl)
            .then((resp) => resp.arrayBuffer())
            .then((buf) => Buffer.from(buf))
            .then((buf) => writeFileSync(distLogFile, buf))
  }

  const { configureMarkdown, vitePlugin } = createBuildTimeDiagramsPlugin({
    diagramsDistDir: 'diagrams',
    ...diagramsPluginOpts,
  })

  configMarkdown = configureMarkdown
  vitePlugins.push(vitePlugin())
}

export default defineConfig({
  lang: 'zh-CN',
  title: 'Kun（鲲）',
  description: 'Kun（鲲）—— 面向 Linux 的函数式脚本语言，项目文档',
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: logo }]],

  markdown: {
    lineNumbers: true,
    theme: {
      light: 'github-light',
      dark: 'one-dark-pro',
    },
    config: (md) => configMarkdown(md),
  },

  themeConfig: {
    logo,

    nav: [
      { text: '首页', link: '/' },
      {
        text: '设计开发',
        items: [
          { text: '项目上下文', link: '/ai-agent/context/' },
          { text: '技术架构', link: '/ai-agent/architecture/' },
          { text: '设计文档', link: '/ai-agent/design/' },
          { text: '工作管理', link: '/ai-agent/backlog/' },
          { text: '历史版本', link: '/ai-agent/archive/' },
        ],
      },
      { text: '版本文档', link: '/v0/' },
    ],

    sidebar: {
      '/': sidebarRoot(),
      '/ai-agent/': sidebarAiAgent(),
      '/ai-agent/context/': sidebarContext(),
      '/ai-agent/architecture/': sidebarArchitecture(),
      '/ai-agent/design/': sidebarDesign(),
      '/ai-agent/process/': sidebarProcess(),
      '/ai-agent/skills/': sidebarSkills(),
      '/ai-agent/backlog/': sidebarWorking(),
      '/ai-agent/plans/': sidebarWorking(),
      '/ai-agent/bugs/': sidebarWorking(),
      '/ai-agent/audits/': sidebarWorking(),
      '/ai-agent/discussions/': sidebarWorking(),
      '/ai-agent/logs/': sidebarWorking(),
      '/ai-agent/testing/': sidebarWorking(),
      '/ai-agent/input/': sidebarWorking(),
      '/ai-agent/requirements/': sidebarWorking(),
      '/ai-agent/references/': sidebarWorking(),
      '/ai-agent/lessons/': sidebarWorking(),
      '/ai-agent/analysis/': sidebarWorking(),
      '/ai-agent/retrospectives/': sidebarWorking(),
      '/ai-agent/examples/': sidebarWorking(),
      '/ai-agent/articles/': sidebarWorking(),
      '/ai-agent/archive/': sidebarArchive(),
      '/v0/': sidebarV0(),
    },

    search: {
      provider: 'local',
      options: {
        locales: {
          root: {
            translations: {
              button: { buttonText: '搜索', buttonAriaLabel: '搜索' },
              modal: {
                noResultsText: '无法找到相关结果',
                resetButtonTitle: '清除查询条件',
                footer: { selectText: '选择', navigateText: '切换', closeText: '关闭' },
              },
            },
          },
        },
      },
    },

    outline: { level: [2, 4], label: '本页目录' },

    docFooter: { prev: '上一页', next: '下一页' },

    lastUpdated: { text: '最后更新于' },

    editLink: {
      pattern: 'https://github.com/crazydan-studio/kun-shell/edit/main/docs/ai-agent/:path',
      text: '在 GitHub 上编辑此页',
    },
  },

  vite: {
    plugins: vitePlugins,
  },

  cleanUrls: true,

  async buildEnd(siteConfig) {
    await fetchLogo(siteConfig.outDir)
  }
})

/* ====== Sidebar helpers ====== */

function sidebarRoot() {
  return [
    {
      text: '首页',
      items: [{ text: '文档中心', link: '/' }],
    },
    { text: '设计开发', link: '/ai-agent/' },
    { text: '版本文档', link: '/v0/' },
  ]
}

function sidebarAiAgent() {
  return [
    {
      text: '设计开发文档',
      items: [
        { text: '概览', link: '/ai-agent/' },
        { text: '项目上下文', link: '/ai-agent/context/' },
        { text: '技术架构', link: '/ai-agent/architecture/' },
        { text: '设计文档', link: '/ai-agent/design/' },
        { text: '开发流程', link: '/ai-agent/process/' },
        { text: '技能库', link: '/ai-agent/skills/' },
        { text: '工作管理', link: '/ai-agent/backlog/' },
        { text: '历史归档', link: '/ai-agent/archive/' },
      ],
    },
    sidebarContext(),
    sidebarArchitecture(),
    sidebarDesign(),
    sidebarProcess(),
    sidebarSkills(),
    sidebarWorking(),
    sidebarArchive(),
  ]
}

function sidebarContext() {
  return [
    {
      text: '项目上下文',
      items: [
        { text: '索引', link: '/ai-agent/context/' },
        { text: '项目上下文', link: '/ai-agent/context/project-context' },
        { text: 'AI 自治策略', link: '/ai-agent/context/ai-autonomy-policy' },
        { text: '代码库地图', link: '/ai-agent/context/codebase-map' },
        { text: '真理源与优先级', link: '/ai-agent/context/source-of-truth-and-precedence' },
        { text: '约定规范', link: '/ai-agent/context/conventions' },
      ],
    },
  ]
}

function sidebarArchitecture() {
  return [
    {
      text: '技术架构',
      items: [
        { text: '索引', link: '/ai-agent/architecture/' },
        { text: '项目愿景', link: '/ai-agent/architecture/project-vision' },
        { text: '系统基线', link: '/ai-agent/architecture/system-baseline' },
        { text: '模块边界', link: '/ai-agent/architecture/module-boundaries' },
      ],
    },
  ]
}

function sidebarDesign() {
  return [
    {
      text: '应用层设计',
      collapsed: false,
      items: [
        { text: '索引', link: '/ai-agent/design/' },
        { text: '应用概览', link: '/ai-agent/design/app-overview' },
        { text: '类型系统', link: '/ai-agent/design/type-system' },
        { text: '标准库', link: '/ai-agent/design/standard-library' },
        { text: '语法设计', link: '/ai-agent/design/syntax' },
        { text: '代码格式化规范', link: '/ai-agent/design/code-formatting' },
        { text: '功能清单', link: '/ai-agent/design/feature-inventory' },
        { text: '安全角色与权限', link: '/ai-agent/design/roles-and-permissions' },
        { text: '供应链安全', link: '/ai-agent/design/supply-chain-security' },
        { text: '命令签名系统', link: '/ai-agent/design/command-signature-system' },
      ],
    },
  ]
}

function sidebarProcess() {
  return [
    {
      text: '开发流程',
      items: [
        { text: '索引', link: '/ai-agent/process/' },
        { text: '应用开发工作流', link: '/ai-agent/process/application-development-workflow' },
      ],
    },
  ]
}

function sidebarSkills() {
  return {
    text: '技能库',
    collapsed: true,
    items: [
      { text: '索引', link: '/ai-agent/skills/' },
      { text: '文档编写规范', link: '/ai-agent/skills/writing-conventions' },
      { text: '文档审计', link: '/ai-agent/skills/document-audit-prompt' },
      { text: '计划审计', link: '/ai-agent/skills/plan-audit-prompt' },
      { text: '闭合审计', link: '/ai-agent/skills/closure-audit-prompt' },
      { text: '多维审计', link: '/ai-agent/skills/multi-dimensional-audit-prompt' },
      { text: '开放式审计', link: '/ai-agent/skills/open-ended-audit-prompt' },
      { text: '需求差距回顾', link: '/ai-agent/skills/requirement-gap-retrospective-prompt' },
    ],
  }
}

function sidebarWorking() {
  return {
    text: '工作管理',
    collapsed: true,
    items: [
      { text: '待办事项', link: '/ai-agent/backlog/' },
      {
        text: '需求文档',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/requirements/' },
          { text: '需求综合指南', link: '/ai-agent/requirements/00-requirement-synthesis-guide' },
          { text: 'MVP', link: '/ai-agent/requirements/mvp' },
          { text: '产品范围', link: '/ai-agent/requirements/product-scope' },
        ],
      },
      {
        text: '开发计划',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/plans/' },
          { text: '计划编写与执行指南', link: '/ai-agent/plans/00-plan-authoring-and-execution-guide' },
          { text: '类型系统核心设计', link: '/ai-agent/plans/plan-type-system-core-design' },
        ],
      },
      {
        text: '讨论记录',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/discussions/' },
          { text: '讨论编写指南', link: '/ai-agent/discussions/00-discussion-writing-guide' },
          { text: '类型系统设计决策', link: '/ai-agent/discussions/discussion-type-system-design-decisions' },
          { text: '语法演进与设计决策', link: '/ai-agent/discussions/discussion-syntax-evolution' },
          { text: '异步支持必要性分析', link: '/ai-agent/discussions/discussion-async-support' },
        ],
      },
      {
        text: 'Bug 修复',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/bugs/' },
          { text: 'Bug 修复记录编写指南', link: '/ai-agent/bugs/00-bug-fix-note-writing-guide' },
        ],
      },
      {
        text: '审计记录',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/audits/' },
          { text: '审计执行指南', link: '/ai-agent/audits/00-audit-execution-guide' },
          { text: '类型系统完备性审计', link: '/ai-agent/audits/audit-type-system-completeness' },
        ],
      },
      {
        text: '开发日志',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/logs/' },
          { text: '日志编写指南', link: '/ai-agent/logs/00-log-writing-guide' },
        ],
      },
      {
        text: '测试记录',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/testing/' },
          { text: '测试记录编写指南', link: '/ai-agent/testing/00-testing-note-guide' },
          { text: '已知良好基线', link: '/ai-agent/testing/known-good-baselines' },
        ],
      },
      {
        text: '参考文档',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/references/' },
          { text: '文档命名与时效性', link: '/ai-agent/references/document-naming-and-timeliness' },
          { text: '实现指南', link: '/ai-agent/references/implementation-guide' },
          { text: '维护检查清单', link: '/ai-agent/references/maintenance-checklist' },
        ],
      },
      {
        text: '输入处理',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/input/' },
          { text: '输入处理指南', link: '/ai-agent/input/00-input-processing-guide' },
          { text: '类型系统会话输入', link: '/ai-agent/input/input-maintainer-type-system-session' },
          { text: '语法规范附件', link: '/ai-agent/input/input-syntax-specification' },
          { text: 'Stream 设计', link: '/ai-agent/input/input-stream-design' },
          { text: '脚本入口与参数', link: '/ai-agent/input/input-entry-point-and-args' },
          { text: '语法细节打磨', link: '/ai-agent/input/input-syntax-polish' },
        ],
      },
      {
        text: '经验教训',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/lessons/' },
          { text: '语法合规审计流程', link: '/ai-agent/lessons/grammar-audit-workflow' },
        ],
      },
      { text: '分析报告', link: '/ai-agent/analysis/' },
      {
        text: '回顾总结',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/retrospectives/' },
          { text: '回顾编写指南', link: '/ai-agent/retrospectives/00-retrospective-writing-guide' },
        ],
      },
      {
        text: '示例',
        collapsed: true,
        items: [
          { text: '索引', link: '/ai-agent/examples/' },
          { text: '日志文件处理器', link: '/ai-agent/examples/file-processor' },
          { text: '类型系统聚焦', link: '/ai-agent/examples/type-showcase' },
          { text: 'IO 与效应系统', link: '/ai-agent/examples/networking' },
          { text: '模式匹配专题', link: '/ai-agent/examples/pattern-matching' },
        ],
      },
      { text: '文章', link: '/ai-agent/articles/' },
    ],
  }
}

function sidebarArchive() {
  return {
    text: '历史版本（归档）',
    collapsed: true,
    items: [
      { text: '索引', link: '/ai-agent/archive/' },
    ],
  }
}

function sidebarV0() {
  return [
    {
      text: 'v0 版本文档',
      items: [
        { text: '概览', link: '/v0/' },
      ],
    },
  ]
}
