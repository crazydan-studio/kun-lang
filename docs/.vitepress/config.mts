import { defineConfig } from 'vitepress'
import { configureDiagramsPlugin, createBuildTimeDiagramsPlugin } from 'vitepress-plugin-diagrams'

const vitePlugins = []
const diagramsPluginOpts = {
  diagramsDir: 'public/diagrams',
  publicPath: '/diagrams',
}
let configMarkdown = (md) => {
  configureDiagramsPlugin(md, diagramsPluginOpts)
}

if (process.env.NODE_ENV == 'production') {
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
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: '/logo.svg' }]],

  markdown: {
    lineNumbers: true,
    theme: {
      light: 'github-light',
      dark: 'one-dark-pro',
    },
    config: (md) => configMarkdown(md),
  },

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: '首页', link: '/' },
      {
        text: '项目上下文',
        items: [
          { text: '项目上下文', link: '/context/project-context' },
          { text: 'AI 自治策略', link: '/context/ai-autonomy-policy' },
          { text: '约定规范', link: '/context/conventions' },
          { text: '代码库地图', link: '/context/codebase-map' },
          { text: '真理源与优先级', link: '/context/source-of-truth-and-precedence' },
        ],
      },
      {
        text: '设计文档',
        items: [
          { text: '应用概览', link: '/design/app-overview' },
          { text: '功能清单', link: '/design/feature-inventory' },
          { text: '安全模型', link: '/design/roles-and-permissions' },
          { text: '项目愿景', link: '/architecture/project-vision' },
          { text: '系统基线', link: '/architecture/system-baseline' },
          { text: '模块边界', link: '/architecture/module-boundaries' },
        ],
      },
      {
        text: '工作管理',
        items: [
          { text: '开发工作流', link: '/process/application-development-workflow' },
          { text: '技能库', link: '/skills/' },
          { text: '待办事项', link: '/backlog/' },
          { text: '需求文档', link: '/requirements/' },
          { text: '开发计划', link: '/plans/' },
        ],
      },
      {
        text: '历史版本',
        items: [
          { text: '版本归档', link: '/archive/' },
        ],
      },
    ],

    sidebar: {
      '/': sidebarRoot(),
      '/context/': sidebarContext(),
      '/architecture/': sidebarArchitecture(),
      '/design/': sidebarDesign(),
      '/process/': sidebarProcess(),
      '/skills/': sidebarSkills(),
      '/backlog/': sidebarWorking(),
      '/plans/': sidebarWorking(),
      '/bugs/': sidebarWorking(),
      '/audits/': sidebarWorking(),
      '/discussions/': sidebarWorking(),
      '/logs/': sidebarWorking(),
      '/testing/': sidebarWorking(),
      '/input/': sidebarWorking(),
      '/requirements/': sidebarWorking(),
      '/references/': sidebarWorking(),
      '/lessons/': sidebarWorking(),
      '/analysis/': sidebarWorking(),
      '/retrospectives/': sidebarWorking(),
      '/examples/': sidebarWorking(),
      '/articles/': sidebarWorking(),
      '/archive/': sidebarArchive(),
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
      pattern: 'https://github.com/crazydan-studio/kun-shell/edit/main/docs/:path',
      text: '在 GitHub 上编辑此页',
    },
  },

  vite: {
    plugins: vitePlugins,
  },

  cleanUrls: true,
})

/* ====== Sidebar helpers ====== */

function sidebarRoot() {
  return [
    {
      text: '首页',
      items: [{ text: '文档中心', link: '/' }],
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
        { text: '索引', link: '/context/' },
        { text: '项目上下文', link: '/context/project-context' },
        { text: 'AI 自治策略', link: '/context/ai-autonomy-policy' },
        { text: '代码库地图', link: '/context/codebase-map' },
        { text: '真理源与优先级', link: '/context/source-of-truth-and-precedence' },
        { text: '约定规范', link: '/context/conventions' },
      ],
    },
  ]
}

function sidebarArchitecture() {
  return [
    {
      text: '技术架构',
      items: [
        { text: '索引', link: '/architecture/' },
        { text: '项目愿景', link: '/architecture/project-vision' },
        { text: '系统基线', link: '/architecture/system-baseline' },
        { text: '模块边界', link: '/architecture/module-boundaries' },
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
        { text: '索引', link: '/design/' },
        { text: '应用概览', link: '/design/app-overview' },
        { text: '功能清单', link: '/design/feature-inventory' },
        { text: '安全角色与权限', link: '/design/roles-and-permissions' },
      ],
    },
  ]
}

function sidebarProcess() {
  return [
    {
      text: '开发流程',
      items: [
        { text: '索引', link: '/process/' },
        { text: '应用开发工作流', link: '/process/application-development-workflow' },
      ],
    },
  ]
}

function sidebarSkills() {
  return {
    text: '技能库',
    collapsed: true,
    items: [
      { text: '索引', link: '/skills/' },
      { text: '文档编写规范', link: '/skills/writing-conventions' },
      { text: '文档审计', link: '/skills/document-audit-prompt' },
      { text: '计划审计', link: '/skills/plan-audit-prompt' },
      { text: '闭合审计', link: '/skills/closure-audit-prompt' },
      { text: '多维审计', link: '/skills/multi-dimensional-audit-prompt' },
      { text: '开放式审计', link: '/skills/open-ended-audit-prompt' },
      { text: '需求差距回顾', link: '/skills/requirement-gap-retrospective-prompt' },
    ],
  }
}

function sidebarWorking() {
  return {
    text: '工作管理',
    collapsed: true,
    items: [
      { text: '待办事项', link: '/backlog/' },
      { text: '需求文档', link: '/requirements/' },
      { text: '开发计划', link: '/plans/' },
      { text: '讨论记录', link: '/discussions/' },
      { text: 'Bug 修复', link: '/bugs/' },
      { text: '审计记录', link: '/audits/' },
      { text: '开发日志', link: '/logs/' },
      { text: '测试记录', link: '/testing/' },
      { text: '参考文档', link: '/references/' },
      { text: '输入处理', link: '/input/' },
      { text: '经验教训', link: '/lessons/' },
      { text: '分析报告', link: '/analysis/' },
      { text: '回顾总结', link: '/retrospectives/' },
      { text: '示例', link: '/examples/' },
      { text: '文章', link: '/articles/' },
    ],
  }
}

function sidebarArchive() {
  return {
    text: '历史版本（归档）',
    collapsed: true,
    items: [
      { text: '索引', link: '/archive/' },
    ],
  }
}
